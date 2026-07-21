#!/bin/bash
set -euo pipefail

admin_user="${LOCALADMIN_USER:-admin}"
admin_password="${LOCALADMIN_PASSWORD:-CHANGE_ME_LOCALADMIN_PASSWORD}"
internal_subnet="${GOS_INTERNAL_SUBNET:?GOS_INTERNAL_SUBNET is required}"
external_subnet="${GOS_EXTERNAL_SUBNET:?GOS_EXTERNAL_SUBNET is required}"
router_internal_ip="${GOS_ROUTER_INTERNAL_IP:?GOS_ROUTER_INTERNAL_IP is required}"
router_external_ip="${GOS_ROUTER_EXTERNAL_IP:?GOS_ROUTER_EXTERNAL_IP is required}"
evil_ip="${GOS_ARM_EVIL_IP:?GOS_ARM_EVIL_IP is required}"
web_ip="${GOS_WEB_INTERNAL_IP:?GOS_WEB_INTERNAL_IP is required}"
mail_ip="${GOS_MAIL_IP:?GOS_MAIL_IP is required}"

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

# Межсетевой экран пропускает только CRM и почтовые протоколы от evil-машины.
# Административный SSH завершается на самом роутере и не попадает в FORWARD.
iptables-restore <<EOF
*filter
:INPUT ACCEPT [0:0]
:FORWARD DROP [0:0]
:OUTPUT ACCEPT [0:0]
-A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
-A FORWARD -i $external_interface -o $internal_interface -s $evil_ip/32 -d $web_ip/32 -p tcp --dport 80 -m conntrack --ctstate NEW -j ACCEPT
-A FORWARD -i $external_interface -o $internal_interface -s $evil_ip/32 -d $mail_ip/32 -p tcp -m multiport --dports 25,143,587 -m conntrack --ctstate NEW -j ACCEPT
COMMIT
EOF

mkdir -p /var/log/suricata /run/suricata
chown -R root:root /var/log/suricata /run/suricata

echo "Router ready: $external_subnet ($external_interface) -> $internal_subnet ($internal_interface)."
echo "Starting passive Suricata IDS on $external_interface."

# -S загружает только контролируемое локальное правило. HOME_NET переопределяется
# из .env, поэтому конфигурация остается переносимой между стендами.
exec suricata \
  -c /etc/suricata/suricata.yaml \
  -i "$external_interface" \
  -S /etc/suricata/rules/gos-local.rules \
  --set "vars.address-groups.HOME_NET=$internal_subnet" \
  --pidfile /run/suricata/suricata.pid
