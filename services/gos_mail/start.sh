#!/bin/bash
# Скрипт запуска почтового сервера.
# На первом старте чистого volume создает конфиги Postfix и Dovecot.
# На последующих стартах сохраняет изменения студента и запускает сервисы.
set -euo pipefail

# Почтовые параметры приходят из .env. Значения по умолчанию нужны
# только для диагностики при ручном запуске контейнера.
mail_domain="${MAIL_DOMAIN:-${GOS_DOMAIN:-gos.local}}"
mail_hostname="${MAIL_HOSTNAME:-mail.${mail_domain}}"
mail_user="${MAIL_USER:-user}"
mail_password="${MAIL_PASSWORD:-CHANGE_ME_MAIL_PASSWORD}"
admin_user="${LOCALADMIN_USER:-localadmin}"
admin_password="${LOCALADMIN_PASSWORD:-CHANGE_ME_LOCALADMIN_PASSWORD}"
external_subnet="${GOS_EXTERNAL_SUBNET:-172.28.8.0/24}"
router_internal_ip="${GOS_ROUTER_INTERNAL_IP:-10.10.20.254}"

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

mail_config_marker="/etc/postfix/.gos-initialized"

# Начальные уязвимые настройки создаются один раз. После marker-файла
# /etc/postfix и /etc/dovecot полностью остаются под управлением студента.
if [[ ! -e "$mail_config_marker" ]]; then
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

  postconf -M submission/inet="submission inet n - y - - smtpd"
  postconf -P submission/inet/syslog_name=postfix/submission
  postconf -P submission/inet/smtpd_sasl_auth_enable=yes
  postconf -P submission/inet/smtpd_relay_restrictions=permit_sasl_authenticated,reject

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

  postfix check
  dovecot -n >/dev/null
  touch "$mail_config_marker"
fi

# Проверяем в том числе сохраненные изменения студента до запуска демонов.
postfix check
dovecot -n >/dev/null

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

# Симметричный обратный маршрут гарантирует, что ответы evil-машине проходят
# через gos_router и наблюдаются Suricata.
ip route replace "$external_subnet" via "$router_internal_ip"

# Общий аудит выключен по умолчанию. Rsyslog автоматически запускается после
# включения общего блока или создания студентом Postfix-правила.
bash /usr/local/bin/gos-rsyslog.sh initialize disabled
bash /usr/local/bin/gos-rsyslog.sh start mail

# Postfix и sshd запускаем как сервисы в фоне, Dovecot держит контейнер в foreground.
postfix start
/usr/sbin/sshd
exec dovecot -F
