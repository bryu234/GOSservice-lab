#!/bin/bash
# Скрипт запуска adm-машины.
# Его задача - подготовить локального администратора, включить SSH
# и затем передать управление штатному XRDP entrypoint базового образа.
set -euo pipefail

# Имя и пароль локального администратора приходят из .env.
# Значения по умолчанию нужны только для безопасного старта при ручном запуске.
admin_user="${LOCALADMIN_USER:-localadmin}"
admin_password="${LOCALADMIN_PASSWORD:-CHANGE_ME_LOCALADMIN_PASSWORD}"
default_user="ubuntu"

# Базовый RDP-образ содержит дефолтного пользователя ubuntu.
# При публикации SSH наружу это опасно: закрываем вход под ним и убираем SSH-ключи.
if id "$default_user" >/dev/null 2>&1 && [ "$default_user" != "$admin_user" ]; then
  pkill -KILL -u "$default_user" >/dev/null 2>&1 || true
  passwd -l "$default_user" >/dev/null 2>&1 || true
  usermod -s /usr/sbin/nologin "$default_user" >/dev/null 2>&1 || true
  rm -rf "/home/$default_user/.ssh"
fi

# Создаем локального пользователя, если контейнер стартует впервые.
if ! id "$admin_user" >/dev/null 2>&1; then
  useradd -m -s /bin/bash "$admin_user"
fi

# Обновляем пароль на каждом старте, чтобы смена LOCALADMIN_PASSWORD в .env
# применялась после перезапуска контейнера.
echo "$admin_user:$admin_password" | chpasswd
usermod -aG sudo "$admin_user"

# Если пакет Wireshark создал группу wireshark, добавляем туда администратора.
# Это понадобится для запуска инструментов анализа трафика из GUI-сессии.
if getent group wireshark >/dev/null 2>&1; then
  usermod -aG wireshark "$admin_user"
fi

# Выдаем локальному администратору sudo-доступ.
cat >/etc/sudoers.d/gos-localadmin <<EOF
$admin_user ALL=(ALL:ALL) ALL
EOF
chmod 0440 /etc/sudoers.d/gos-localadmin

# Готовим runtime-директорию SSHD и генерируем host keys, если их еще нет.
mkdir -p /run/sshd
chmod 755 /run/sshd
ssh-keygen -A >/dev/null 2>&1 || true

# В лабораторной SSH включен по паролю для простого подключения.
# Root-login запрещен, вход выполняется под LOCALADMIN_USER.
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config || true
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config || true
sed -i '/^AllowUsers /d' /etc/ssh/sshd_config || true
echo "AllowUsers $admin_user" >>/etc/ssh/sshd_config

# Запускаем системные логи и SSH. rsyslog может ругаться на /proc/kmsg
# внутри контейнера, поэтому ошибка не должна валить весь контейнер.
rsyslogd || true
/usr/sbin/sshd

# В scottyhardy/docker-remote-desktop основной RDP/XRDP запуск спрятан
# в /usr/bin/entrypoint. После нашей подготовки передаем управление ему.
if [ -x /usr/bin/entrypoint ]; then
  exec /usr/bin/entrypoint "$@"
fi

# Fallback на случай изменения базового образа: держим контейнер живым,
# чтобы можно было зайти внутрь и диагностировать проблему.
tail -f /dev/null
