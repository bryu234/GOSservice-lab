#!/bin/bash
# Скрипт запуска почтового сервера.
# На каждом старте:
# - создает системного пользователя для mailbox;
# - обновляет пароль из .env;
# - генерирует минимальные конфиги Postfix и Dovecot;
# - запускает SMTP и IMAP сервисы.
set -euo pipefail

# Почтовые параметры приходят из .env. Значения по умолчанию нужны
# только для диагностики при ручном запуске контейнера.
mail_domain="${MAIL_DOMAIN:-${GOS_DOMAIN:-gos.local}}"
mail_hostname="${MAIL_HOSTNAME:-mail.${mail_domain}}"
mail_user="${MAIL_USER:-user}"
mail_password="${MAIL_PASSWORD:-CHANGE_ME_MAIL_PASSWORD}"

# Создаем локального пользователя, чей домашний каталог хранится в volume.
# Dovecot использует системную PAM-аутентификацию, поэтому отдельной БД паролей нет.
if ! id "$mail_user" >/dev/null 2>&1; then
  useradd -m -s /usr/sbin/nologin "$mail_user"
fi

# Обновляем пароль на каждом старте, чтобы смена MAIL_PASSWORD в .env
# применялась после перезапуска контейнера.
echo "$mail_user:$mail_password" | chpasswd

# Maildir-структура нужна Postfix для доставки писем и Dovecot для чтения IMAP.
mail_home="$(getent passwd "$mail_user" | cut -d: -f6)"
for dir in "$mail_home/Maildir" "$mail_home/Maildir/cur" "$mail_home/Maildir/new" "$mail_home/Maildir/tmp"; do
  install -d -m 700 -o "$mail_user" -g "$mail_user" "$dir"
done

# Настраиваем Postfix как внутренний SMTP-сервер лабораторного домена.
# mynetworks намеренно открыт на весь IPv4 для учебной misconfiguration.
postconf -e "myhostname = ${mail_hostname}"
postconf -e "mydomain = ${mail_domain}"
postconf -e "myorigin = \$mydomain"
postconf -e "inet_interfaces = all"
postconf -e "inet_protocols = ipv4"
postconf -e "mydestination = \$myhostname, localhost.\$mydomain, localhost, \$mydomain"
postconf -e "home_mailbox = Maildir/"
postconf -e "mynetworks = 0.0.0.0/0"
postconf -e "smtpd_relay_restrictions = permit_mynetworks, permit_sasl_authenticated, defer_unauth_destination"
postconf -e "smtpd_sasl_type = dovecot"
postconf -e "smtpd_sasl_path = private/auth"
postconf -e "smtpd_sasl_auth_enable = yes"
postconf -e "smtpd_tls_security_level = none"
postconf -e "smtp_tls_security_level = none"

# Включаем порт 587 для Thunderbird. Он требует авторизацию через Dovecot SASL.
postconf -M submission/inet="submission inet n - y - - smtpd"
postconf -P submission/inet/syslog_name=postfix/submission
postconf -P submission/inet/smtpd_sasl_auth_enable=yes
postconf -P submission/inet/smtpd_relay_restrictions=permit_sasl_authenticated,reject

# Dovecot отдает Maildir по IMAP и предоставляет Postfix unix-socket для SASL.
cat >/etc/dovecot/local.conf <<EOF
protocols = imap lmtp
listen = *
disable_plaintext_auth = no
auth_mechanisms = plain login
mail_location = maildir:~/Maildir

service imap-login {
  inet_listener imap {
    port = 143
  }
}

service auth {
  unix_listener /var/spool/postfix/private/auth {
    mode = 0660
    user = postfix
    group = postfix
  }
}

ssl = no
EOF

# Проверяем конфигурации до запуска демонов.
postfix check
dovecot -n >/dev/null

# Логирование почты в /var/log/mail.log намеренно отключено.
# Если файл создали вручную во время диагностики, удаляем его при старте.
rm -f /var/log/mail.log

# Postfix запускаем как сервис в фоне, Dovecot держит контейнер в foreground.
postfix start
exec dovecot -F
