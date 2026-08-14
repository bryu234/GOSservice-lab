#!/bin/bash
set -euo pipefail

admin_user="${LOCALADMIN_USER:-admin}"
admin_password="${LOCALADMIN_PASSWORD:-CHANGE_ME_LOCALADMIN_PASSWORD}"
internal_subnet="${GOS_INTERNAL_SUBNET:?GOS_INTERNAL_SUBNET is required}"
external_subnet="${GOS_EXTERNAL_SUBNET:?GOS_EXTERNAL_SUBNET is required}"
router_internal_ip="${GOS_ROUTER_INTERNAL_IP:?GOS_ROUTER_INTERNAL_IP is required}"
router_external_ip="${GOS_ROUTER_EXTERNAL_IP:?GOS_ROUTER_EXTERNAL_IP is required}"
evil_ip="${GOS_ARM_EVIL_IP:?GOS_ARM_EVIL_IP is required}"
dns_ip="${GOS_DNS_IP:?GOS_DNS_IP is required}"
web_ip="${GOS_WEB_INTERNAL_IP:?GOS_WEB_INTERNAL_IP is required}"
mail_ip="${GOS_MAIL_IP:?GOS_MAIL_IP is required}"
firewall_state_dir="/var/lib/gos-router-firewall"
firewall_state_file="$firewall_state_dir/iptables.rules"
firewall_restore_file="/run/gos-router-iptables.rules"
firewall_expanded_file="/run/gos-router-iptables-expanded.rules"
docker_dns_rules_file="/run/gos-router-docker-dns.rules"

interface_for_ip() {
  local expected_ip="$1"
  ip -o -4 addr show | awk -v expected="$expected_ip" '
    {
      split($4, address, "/")
      if (address[1] == expected) {
        print $2
        exit
      }
    }
  '
}

internal_interface="$(interface_for_ip "$router_internal_ip")"
external_interface="$(interface_for_ip "$router_external_ip")"

if [ -z "$internal_interface" ] || [ -z "$external_interface" ]; then
  echo "Cannot identify router interfaces for $router_internal_ip and $router_external_ip." >&2
  ip -o -4 addr show >&2
  exit 1
fi

apply_default_firewall() {
  # Межсетевой экран по умолчанию пропускает DNS, учебный сайт и почтовые протоколы
  # от evil-машины. SSH завершается на самом роутере и не попадает в FORWARD.
  iptables-restore <<EOF
*filter
:INPUT ACCEPT [0:0]
:FORWARD DROP [0:0]
:OUTPUT ACCEPT [0:0]
-A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
-A FORWARD -i $external_interface -o $internal_interface -s $evil_ip/32 -d $dns_ip/32 -p tcp --dport 53 -m conntrack --ctstate NEW -j ACCEPT
-A FORWARD -i $external_interface -o $internal_interface -s $evil_ip/32 -d $dns_ip/32 -p udp --dport 53 -m conntrack --ctstate NEW -j ACCEPT
-A FORWARD -i $external_interface -o $internal_interface -s $evil_ip/32 -d $web_ip/32 -p tcp --dport 80 -m conntrack --ctstate NEW -j ACCEPT
-A FORWARD -i $external_interface -o $internal_interface -s $evil_ip/32 -d $mail_ip/32 -p tcp -m multiport --dports 25,143,587 -m conntrack --ctstate NEW -j ACCEPT
COMMIT
EOF
}

normalize_firewall_interfaces() {
  # Docker может поменять eth0/eth1 местами при пересоздании контейнера.
  # В persistent-снимке заменяем точные -i/-o ссылки логическими маркерами.
  awk \
    -v internal="$internal_interface" \
    -v external="$external_interface" \
    '
      {
        for (i = 1; i < NF; i++) {
          if ($i == "-i" || $i == "--in-interface" || $i == "-o" || $i == "--out-interface") {
            if ($(i + 1) == internal) {
              $(i + 1) = "__GOS_INTERNAL_INTERFACE__"
            } else if ($(i + 1) == external) {
              $(i + 1) = "__GOS_EXTERNAL_INTERFACE__"
            }
          }
        }
        print
      }
    '
}

expand_firewall_interfaces() {
  awk \
    -v internal="$internal_interface" \
    -v external="$external_interface" \
    '
      {
        for (i = 1; i < NF; i++) {
          if ($i == "-i" || $i == "--in-interface" || $i == "-o" || $i == "--out-interface") {
            if ($(i + 1) == "__GOS_INTERNAL_INTERFACE__") {
              $(i + 1) = internal
            } else if ($(i + 1) == "__GOS_EXTERNAL_INTERFACE__") {
              $(i + 1) = external
            }
          }
        }
        print
      }
    '
}

extract_docker_dns_rules() {
  # Docker создает внутри network namespace служебные NAT-правила для
  # 127.0.0.11 с динамическими портами. Эти правила нельзя переносить из
  # старого контейнера, поэтому при восстановлении берем их из текущего.
  awk '
    /^:DOCKER_(OUTPUT|POSTROUTING) / ||
    /^-A DOCKER_(OUTPUT|POSTROUTING) / ||
    /^-A (OUTPUT|POSTROUTING) .* -j DOCKER_(OUTPUT|POSTROUTING)( |$)/
  '
}

merge_current_docker_dns_rules() {
  local saved_rules_file="$1"
  local current_docker_rules_file="$2"

  awk -v docker_file="$current_docker_rules_file" '
    function is_docker_dns_rule(line) {
      return line ~ /^:DOCKER_(OUTPUT|POSTROUTING) / ||
        line ~ /^-A DOCKER_(OUTPUT|POSTROUTING) / ||
        line ~ /^-A (OUTPUT|POSTROUTING) .* -j DOCKER_(OUTPUT|POSTROUTING)( |$)/
    }

    FILENAME == docker_file {
      docker_rules[++docker_rule_count] = $0
      next
    }

    /^\*nat$/ {
      in_nat = 1
      print
      next
    }

    in_nat && /^COMMIT$/ {
      for (i = 1; i <= docker_rule_count; i++) {
        print docker_rules[i]
      }
      in_nat = 0
      print
      next
    }

    in_nat && is_docker_dns_rule($0) {
      next
    }

    {
      print
    }
  ' "$current_docker_rules_file" "$saved_rules_file"
}

save_firewall_state() {
  local temporary_file="$firewall_state_file.tmp"

  mkdir -p "$firewall_state_dir"
  chmod 0700 "$firewall_state_dir"

  if iptables-save | normalize_firewall_interfaces >"$temporary_file"; then
    chmod 0600 "$temporary_file"
    mv -f "$temporary_file" "$firewall_state_file"
    echo "Saved iptables state to $firewall_state_file."
  else
    rm -f "$temporary_file"
    echo "Failed to save iptables state; keeping the previous snapshot." >&2
    return 1
  fi
}

restore_firewall_state() {
  if [ ! -s "$firewall_state_file" ]; then
    echo "No saved iptables state found; applying repository defaults."
    apply_default_firewall
    return
  fi

  mkdir -p "$(dirname "$firewall_restore_file")"
  expand_firewall_interfaces <"$firewall_state_file" >"$firewall_expanded_file"
  iptables-save -t nat | extract_docker_dns_rules >"$docker_dns_rules_file"
  merge_current_docker_dns_rules \
    "$firewall_expanded_file" \
    "$docker_dns_rules_file" \
    >"$firewall_restore_file"

  if iptables-restore --test <"$firewall_restore_file" \
    && iptables-restore <"$firewall_restore_file"; then
    echo "Restored iptables state from $firewall_state_file."
  else
    echo "Saved iptables state is invalid; applying repository defaults." >&2
    apply_default_firewall
  fi

  rm -f "$firewall_restore_file" "$firewall_expanded_file" "$docker_dns_rules_file"
}

# Создаем ту же административную учетную запись, что используется на остальных
# внутренних сервисах. Стандартный ubuntu-пользователь не должен оставаться доступным.
if id ubuntu >/dev/null 2>&1 && [ "$admin_user" != "ubuntu" ]; then
  pkill -KILL -u ubuntu >/dev/null 2>&1 || true
  passwd -l ubuntu >/dev/null 2>&1 || true
  usermod -s /usr/sbin/nologin ubuntu >/dev/null 2>&1 || true
  rm -rf /home/ubuntu/.ssh
fi

if ! id "$admin_user" >/dev/null 2>&1; then
  useradd -m -s /bin/bash "$admin_user"
fi

echo "$admin_user:$admin_password" | chpasswd
usermod -aG sudo "$admin_user"

cat >/etc/sudoers.d/gos-localadmin <<EOF
$admin_user ALL=(ALL:ALL) ALL
EOF
chmod 0440 /etc/sudoers.d/gos-localadmin

mkdir -p /run/sshd
chmod 755 /run/sshd
ssh-keygen -A >/dev/null 2>&1 || true
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config || true
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config || true
# PAM-сессия в минимальном router-контейнере не нужна и мешает sshd создать
# дочерний shell-процесс после успешной парольной аутентификации.
sed -i 's/^#\?UsePAM.*/UsePAM no/' /etc/ssh/sshd_config || true
sed -i '/^AllowUsers /d' /etc/ssh/sshd_config || true
sed -i '/^ListenAddress /d' /etc/ssh/sshd_config || true
echo "AllowUsers $admin_user" >>/etc/ssh/sshd_config
echo "ListenAddress $router_internal_ip" >>/etc/ssh/sshd_config
/usr/sbin/sshd

# Маршрутизация включается compose-параметром sysctls. Повторная запись в
# /proc/sys внутри Docker Desktop может быть read-only, поэтому здесь проверяем
# итоговое значение и падаем с понятной ошибкой вместо шумного warning.
if [ "$(cat /proc/sys/net/ipv4/ip_forward)" != "1" ]; then
  echo "net.ipv4.ip_forward must be enabled for gos_router." >&2
  exit 1
fi

restore_firewall_state

mkdir -p /var/log/suricata /run/suricata
chown -R root:root /var/log/suricata /run/suricata

# Docker restart сохраняет writable layer контейнера, поэтому после аварийной
# остановки здесь может остаться PID предыдущего процесса Suricata. В новом
# PID namespace этот файл всегда устаревший и не должен блокировать запуск.
suricata_pidfile="/run/suricata/suricata.pid"
rm -f "$suricata_pidfile"

echo "Router ready: $external_subnet ($external_interface) -> $internal_subnet ($internal_interface)."
echo "Starting passive Suricata IDS on $external_interface."

# -S загружает только контролируемое локальное правило. HOME_NET переопределяется
# из .env, поэтому конфигурация остается переносимой между стендами.
suricata \
  -c /etc/suricata/suricata.yaml \
  -i "$external_interface" \
  -S /etc/suricata/rules/gos-local.rules \
  --set "vars.address-groups.HOME_NET=$internal_subnet" \
  --pidfile "$suricata_pidfile" &
suricata_pid=$!

shutdown_router() {
  local signal="${1:-TERM}"

  trap - TERM INT
  echo "Received $signal; saving firewall state and stopping router services."
  save_firewall_state || true

  if kill -0 "$suricata_pid" >/dev/null 2>&1; then
    kill "-$signal" "$suricata_pid" >/dev/null 2>&1 || true
    wait "$suricata_pid" || true
  fi

  exit 0
}

trap 'shutdown_router TERM' TERM
trap 'shutdown_router INT' INT

set +e
wait "$suricata_pid"
suricata_status=$?
set -e

echo "Suricata exited with status $suricata_status; saving firewall state." >&2
save_firewall_state || true
exit "$suricata_status"
