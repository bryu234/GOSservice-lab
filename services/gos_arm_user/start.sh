#!/bin/bash
# Скрипт запуска user-машины.
# Его задача - подготовить обычного пользователя, включить SSH
# и затем передать управление штатному XRDP entrypoint базового образа.
set -euo pipefail

# Имя и пароль пользователя приходят из .env.
# Значения по умолчанию нужны только для безопасного старта при ручном запуске.
user_name="${USER_USERNAME:-user}"
user_password="${USER_PASSWORD:-CHANGE_ME_USER_PASSWORD}"
admin_user="${LOCALADMIN_USER:-localadmin}"
admin_password="${LOCALADMIN_PASSWORD:-CHANGE_ME_LOCALADMIN_PASSWORD}"
mail_domain="${MAIL_DOMAIN:-${GOS_DOMAIN:-gos.local}}"
mail_user="${MAIL_USER:-$user_name}"
mail_address="${mail_user}@${mail_domain}"
imap_host="imap.${mail_domain}"
smtp_host="smtp.${mail_domain}"
default_user="ubuntu"

# Базовый RDP-образ содержит дефолтного пользователя ubuntu.
# В лабораторной должны работать только USER_USERNAME и LOCALADMIN_USER.
if id "$default_user" >/dev/null 2>&1 && [ "$default_user" != "$user_name" ] && [ "$default_user" != "$admin_user" ]; then
  pkill -KILL -u "$default_user" >/dev/null 2>&1 || true
  passwd -l "$default_user" >/dev/null 2>&1 || true
  usermod -s /usr/sbin/nologin "$default_user" >/dev/null 2>&1 || true
  rm -rf "/home/$default_user/.ssh"
fi

# Создаем локального пользователя, если контейнер стартует впервые.
if ! id "$user_name" >/dev/null 2>&1; then
  useradd -m -s /bin/bash "$user_name"
fi

# Обновляем пароль на каждом старте, чтобы смена USER_PASSWORD в .env
# применялась после перезапуска контейнера.
echo "$user_name:$user_password" | chpasswd

# Дополнительная админская учетная запись нужна для установки пакетов
# и диагностики user-машины с adm под тем же LOCALADMIN_USER.
if ! id "$admin_user" >/dev/null 2>&1; then
  useradd -m -s /bin/bash "$admin_user"
fi

echo "$admin_user:$admin_password" | chpasswd
usermod -aG sudo "$admin_user"

cat >/etc/sudoers.d/gos-localadmin <<EOF
$admin_user ALL=(ALL:ALL) ALL
EOF
chmod 0440 /etc/sudoers.d/gos-localadmin

# Готовим runtime-директорию SSHD и генерируем host keys, если их еще нет.
mkdir -p /run/sshd
chmod 755 /run/sshd
ssh-keygen -A >/dev/null 2>&1 || true

# В лабораторной SSH включен по паролю для простого подключения.
# Root-login запрещен, вход выполняется под USER_USERNAME.
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config || true
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config || true
sed -i '/^AllowUsers /d' /etc/ssh/sshd_config || true
echo "AllowUsers $user_name $admin_user" >>/etc/ssh/sshd_config

# Запускаем локальный системный аудит и SSHD. Ошибка чтения /proc/kmsg внутри
# контейнера не должна мешать запуску пользовательской станции.
rm -f /run/rsyslogd.pid
rsyslogd || true
/usr/sbin/sshd

# Создаем готовый профиль Thunderbird с настроенным почтовым аккаунтом.
# Пароль не сохраняем в профиле: пользователь вводит MAIL_PASSWORD при первом входе.
thunderbird_dir="/home/$user_name/.thunderbird"
profile_name="gos.default"
profile_dir="$thunderbird_dir/$profile_name"
install_id="GOSLAB"

install -d -m 700 -o "$user_name" -g "$user_name" "$profile_dir"

cat >"$thunderbird_dir/profiles.ini" <<EOF
[Install${install_id}]
Default=${profile_name}
Locked=1

[Profile0]
Name=gos
IsRelative=1
Path=${profile_name}
Default=1

[General]
StartWithLastProfile=1
Version=2
EOF

cat >"$profile_dir/prefs.js" <<EOF
user_pref("mail.account.account1.identities", "id1");
user_pref("mail.account.account1.server", "server1");
user_pref("mail.accountmanager.accounts", "account1");
user_pref("mail.accountmanager.defaultaccount", "account1");
user_pref("mail.identity.id1.fullName", "${user_name}");
user_pref("mail.identity.id1.smtpServer", "smtp1");
user_pref("mail.identity.id1.useremail", "${mail_address}");
user_pref("mail.identity.id1.valid", true);
user_pref("mail.server.server1.authMethod", 3);
user_pref("mail.server.server1.check_new_mail", true);
user_pref("mail.server.server1.hostname", "${imap_host}");
user_pref("mail.server.server1.login_at_startup", true);
user_pref("mail.server.server1.name", "${mail_address}");
user_pref("mail.server.server1.port", 143);
user_pref("mail.server.server1.socketType", 0);
user_pref("mail.server.server1.type", "imap");
user_pref("mail.server.server1.userName", "${mail_user}");
user_pref("mail.smtp.defaultserver", "smtp1");
user_pref("mail.smtpserver.smtp1.authMethod", 3);
user_pref("mail.smtpserver.smtp1.hostname", "${smtp_host}");
user_pref("mail.smtpserver.smtp1.port", 587);
user_pref("mail.smtpserver.smtp1.try_ssl", 0);
user_pref("mail.smtpserver.smtp1.username", "${mail_user}");
user_pref("mail.smtpservers", "smtp1");
EOF

chown -R "$user_name:$user_name" "$thunderbird_dir"
chmod 700 "$thunderbird_dir" "$profile_dir"

# Запускаем XRDP напрямую, без /usr/bin/entrypoint базового образа.
# Базовый entrypoint пересоздает дефолтного пользователя ubuntu, поэтому
# здесь намеренно запускаются только нужные RDP-процессы.
rm -f /run/xrdp/xrdp.pid /run/xrdp/xrdp-sesman.pid
/usr/sbin/xrdp-sesman
exec /usr/sbin/xrdp --nodaemon
