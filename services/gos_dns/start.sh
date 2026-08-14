#!/bin/bash
# Скрипт запуска DNS-машины.
# Конфиги Bind9 создаются только при первом старте чистого persistent volume.
set -euo pipefail

# Домен лабораторной по умолчанию - gos.local.
domain="${GOS_DOMAIN:-gos.local}"
admin_user="${LOCALADMIN_USER:-localadmin}"
admin_password="${LOCALADMIN_PASSWORD:-CHANGE_ME_LOCALADMIN_PASSWORD}"
external_subnet="${GOS_EXTERNAL_SUBNET:?GOS_EXTERNAL_SUBNET is required}"
router_internal_ip="${GOS_ROUTER_INTERNAL_IP:?GOS_ROUTER_INTERNAL_IP is required}"

bind_marker="/etc/bind/.gos-initialized"

# Первый запуск наполняет конфигурационный volume из переменных стенда. После
# создания marker-файла все изменения в /etc/bind принадлежат студенту.
if [[ ! -e "$bind_marker" ]]; then
  serial="$(date +%Y%m%d%H)"

  cat >/etc/bind/named.conf.options <<EOF
options {
  directory "/var/cache/bind";
  dnssec-validation no;
  listen-on port 53 { any; };
  listen-on-v6 { none; };
  allow-query { any; };
  recursion yes;
  forwarders {
    1.1.1.1;
    8.8.8.8;
  };
};

/*
logging {
  channel named_log {
    file "/var/log/bind/named.log" versions 3 size 5m;
    severity info;
    print-time yes;
    print-category yes;
    print-severity yes;
  };

  channel query_log {
    file "/var/log/bind/query.log" versions 3 size 5m;
    severity info;
    print-time yes;
    print-category yes;
    print-severity yes;
  };

  category default { named_log; };
  category security { named_log; };
  category queries { query_log; };
};
*/
EOF

  cat >/etc/bind/named.conf.local <<EOF
zone "$domain" {
  type master;
  file "/etc/bind/db.$domain";
};
EOF

  cat >/etc/bind/db.$domain <<EOF
\$ORIGIN $domain.
\$TTL 300
@ IN SOA dns.$domain. admin.$domain. (
  $serial
  3600
  900
  604800
  300 )

@              IN NS dns.$domain.
@              IN MX 10 mail.$domain.
dns            IN A  ${GOS_DNS_IP}
adm            IN A  ${GOS_ARM_ADM_IP}
user           IN A  ${GOS_ARM_USER_IP}
router         IN A  ${GOS_ROUTER_INTERNAL_IP}
site           IN A  ${GOS_WEB_INTERNAL_IP}
db             IN A  ${GOS_DB_IP}
mail           IN A  ${GOS_MAIL_IP}
smtp           IN A  ${GOS_MAIL_IP}
imap           IN A  ${GOS_MAIL_IP}
wazuh          IN A  ${GOS_WAZUH_MANAGER_IP}
wazuh-indexer  IN A  ${GOS_WAZUH_INDEXER_IP}
siem           IN A  ${GOS_WAZUH_DASHBOARD_IP}
EOF

  named-checkconf
  named-checkzone "$domain" "/etc/bind/db.$domain"
  touch "$bind_marker"
fi

# Каталог журналов не является volume, поэтому восстанавливаем его при каждом
# пересоздании контейнера. Сам logging-блок студент включает в /etc/bind.
install -d -m 0750 -o bind -g bind /var/log/bind

# Ошибочная правка не должна запускать named с поврежденной конфигурацией.
named-checkconf
if [[ -f "/etc/bind/db.$domain" ]]; then
  named-checkzone "$domain" "/etc/bind/db.$domain"
fi

# Локальный администратор нужен для SSH-доступа с adm-машины.
if ! id "$admin_user" >/dev/null 2>&1; then
  useradd -m -s /bin/bash "$admin_user"
fi

echo "$admin_user:$admin_password" | chpasswd
usermod -aG sudo "$admin_user"

cat >/etc/sudoers.d/gos-localadmin <<EOF
$admin_user ALL=(ALL:ALL) ALL
EOF
chmod 0440 /etc/sudoers.d/gos-localadmin

# Включаем SSH по паролю только для внутренних лабораторных подключений.
mkdir -p /run/sshd
chmod 755 /run/sshd
ssh-keygen -A >/dev/null 2>&1 || true
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config || true
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config || true

# Ответы evil-машине должны возвращаться через gos_router, чтобы DNS-трафик
# проходил через управляемые студентом правила FORWARD в обоих направлениях.
ip route replace "$external_subnet" via "$router_internal_ip"

# На DNS rsyslog установлен, но намеренно не включен автоматически.
# named запускается в foreground, чтобы контейнер жил пока жив DNS-сервер.
/usr/sbin/sshd
exec named -g -u bind
