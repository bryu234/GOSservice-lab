#!/bin/bash
# Скрипт запуска user-машины.
# Его задача - подготовить обычного пользователя, включить SSH
# и затем передать управление штатному XRDP entrypoint базового образа.
set -euo pipefail

# Имя и пароль пользователя приходят из .env.
# Значения по умолчанию нужны только для безопасного старта при ручном запуске.
user_name="${USER_USERNAME:-user}"
user_password="${USER_PASSWORD:-CHANGE_ME_USER_PASSWORD}"

# Создаем локального пользователя, если контейнер стартует впервые.
if ! id "$user_name" >/dev/null 2>&1; then
  useradd -m -s /bin/bash "$user_name"
fi

# Обновляем пароль на каждом старте, чтобы смена USER_PASSWORD в .env
# применялась после перезапуска контейнера.
echo "$user_name:$user_password" | chpasswd

# Готовим runtime-директорию SSHD и генерируем host keys, если их еще нет.
mkdir -p /run/sshd
chmod 755 /run/sshd
ssh-keygen -A >/dev/null 2>&1 || true

# В лабораторной SSH включен по паролю для простого подключения.
# Root-login запрещен, вход выполняется под USER_USERNAME.
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config || true
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config || true

# Запускаем SSHD. В отличие от adm-машины, sudo и инструменты анализа трафика
# здесь не настраиваются, потому что это обычная пользовательская станция.
/usr/sbin/sshd

# В scottyhardy/docker-remote-desktop основной RDP/XRDP запуск спрятан
# в /usr/bin/entrypoint. После нашей подготовки передаем управление ему.
if [ -x /usr/bin/entrypoint ]; then
  exec /usr/bin/entrypoint "$@"
fi

# Fallback на случай изменения базового образа: держим контейнер живым,
# чтобы можно было зайти внутрь и диагностировать проблему.
tail -f /dev/null
