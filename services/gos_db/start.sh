#!/usr/bin/env bash
# Скрипт запуска DB-сервера.
# Создает локального администратора для SSH, запускает sshd
# и затем передает управление штатному entrypoint MariaDB.
set -euo pipefail

admin_user="${LOCALADMIN_USER:-localadmin}"
admin_password="${LOCALADMIN_PASSWORD:-CHANGE_ME_LOCALADMIN_PASSWORD}"

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
/usr/sbin/sshd

# Официальный entrypoint MariaDB выполняет инициализацию datadir и запуск mariadbd.
exec docker-entrypoint.sh "$@"
