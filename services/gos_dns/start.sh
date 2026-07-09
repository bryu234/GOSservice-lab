#!/bin/bash
# Скрипт запуска DNS-машины.
# На каждом старте генерирует конфиги Bind9 из переменных окружения,
# чтобы IP-адреса можно было менять через .env без ручного редактирования зоны.
set -euo pipefail

# Домен лабораторной по умолчанию - gos.local.
domain="${GOS_DOMAIN:-gos.local}"

# Serial зоны строится из текущей даты/часа. Этого достаточно для лабораторной,
# где зона генерируется заново при старте контейнера.
serial="$(date +%Y%m%d%H)"

# Основные настройки Bind9:
# - слушаем все интерфейсы контейнера;
# - разрешаем запросы из docker-сетей;
# - включаем рекурсию для внешних доменов;
# - пересылаем внешние запросы на публичные DNS;
# - проверка подписей намеренно не настроена для учебной правки.
cat >/etc/bind/named.conf.options <<EOF
options {
  directory "/var/cache/bind";
  listen-on port 53 { any; };
  listen-on-v6 { none; };
  allow-query { any; };
  recursion yes;
  forwarders {
    1.1.1.1;
    8.8.8.8;
  };
};

// logging {
//   channel named_log {
//     file "/var/log/bind/named.log" versions 3 size 5m;
//     severity info;
//     print-time yes;
//     print-category yes;
//     print-severity yes;
//   };
//
//   channel query_log {
//     file "/var/log/bind/query.log" versions 3 size 5m;
//     severity info;
//     print-time yes;
//     print-category yes;
//     print-severity yes;
//   };
//
//   category default { named_log; };
//   category security { named_log; };
//   category queries { query_log; };
// };
EOF

# Подключаем master-зону лабораторного домена.
cat >/etc/bind/named.conf.local <<EOF
zone "$domain" {
  type master;
  file "/etc/bind/db.$domain";
};
EOF

# Генерируем прямую DNS-зону.
# В именах используются дефисы, потому что underscore в DNS owner names
# rejected by Bind check-names и ломает загрузку зоны.
cat >/etc/bind/db.$domain <<EOF
\$ORIGIN $domain.
\$TTL 300
@ IN SOA ns.$domain. admin.$domain. (
  $serial
  3600
  900
  604800
  300 )

@              IN NS ns.$domain.
@              IN MX 10 mail.$domain.
ns             IN A  ${GOS_DNS_IP}
dns            IN A  ${GOS_DNS_IP}
gos-dns        IN A  ${GOS_DNS_IP}
adm            IN A  ${GOS_ARM_ADM_IP}
gos-arm-adm    IN A  ${GOS_ARM_ADM_IP}
user           IN A  ${GOS_ARM_USER_IP}
gos-arm-user   IN A  ${GOS_ARM_USER_IP}
crm            IN A  ${GOS_WEB_INTERNAL_IP}
web            IN A  ${GOS_WEB_INTERNAL_IP}
gos-web        IN A  ${GOS_WEB_INTERNAL_IP}
db             IN A  ${GOS_DB_IP}
gos-db         IN A  ${GOS_DB_IP}
mail           IN A  ${GOS_MAIL_IP}
smtp           IN A  ${GOS_MAIL_IP}
imap           IN A  ${GOS_MAIL_IP}
gos-mail       IN A  ${GOS_MAIL_IP}
wazuh          IN A  ${GOS_WAZUH_MANAGER_IP}
wazuh-manager  IN A  ${GOS_WAZUH_MANAGER_IP}
gos-siem-manager IN A ${GOS_WAZUH_MANAGER_IP}
wazuh-indexer  IN A  ${GOS_WAZUH_INDEXER_IP}
gos-siem-indexer IN A ${GOS_WAZUH_INDEXER_IP}
siem           IN A  ${GOS_WAZUH_DASHBOARD_IP}
wazuh-dashboard IN A ${GOS_WAZUH_DASHBOARD_IP}
gos-siem       IN A  ${GOS_WAZUH_DASHBOARD_IP}
EOF

# Проверяем синтаксис Bind-конфигов до запуска named.
named-checkconf
named-checkzone "$domain" "/etc/bind/db.$domain"

# rsyslog запускается как вспомогательный сервис логирования.
# named запускается в foreground, чтобы контейнер жил пока жив DNS-сервер.
rsyslogd || true
exec named -g -u bind
