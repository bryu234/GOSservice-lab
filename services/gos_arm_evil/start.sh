#!/bin/bash
set -euo pipefail

evil_user="${EVIL_USERNAME:-evil}"
evil_password="${EVIL_PASSWORD:-CHANGE_ME_EVIL_PASSWORD}"
internal_subnet="${GOS_INTERNAL_SUBNET:?GOS_INTERNAL_SUBNET is required}"
router_external_ip="${GOS_ROUTER_EXTERNAL_IP:?GOS_ROUTER_EXTERNAL_IP is required}"

if id ubuntu >/dev/null 2>&1 && [ "$evil_user" != "ubuntu" ]; then
  pkill -KILL -u ubuntu >/dev/null 2>&1 || true
  passwd -l ubuntu >/dev/null 2>&1 || true
  usermod -s /usr/sbin/nologin ubuntu >/dev/null 2>&1 || true
  rm -rf /home/ubuntu/.ssh
fi

if ! id "$evil_user" >/dev/null 2>&1; then
  useradd -m -s /bin/bash "$evil_user"
fi

echo "$evil_user:$evil_password" | chpasswd
usermod -aG sudo "$evil_user"

if getent group wireshark >/dev/null 2>&1; then
  usermod -aG wireshark "$evil_user"
fi

cat >/etc/sudoers.d/gos-evil <<EOF
$evil_user ALL=(ALL:ALL) ALL
EOF
chmod 0440 /etc/sudoers.d/gos-evil

mkdir -p /run/sshd
chmod 755 /run/sshd
ssh-keygen -A >/dev/null 2>&1 || true
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config || true
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config || true
sed -i '/^AllowUsers /d' /etc/ssh/sshd_config || true
echo "AllowUsers $evil_user" >>/etc/ssh/sshd_config

# Более специфичный маршрут не дает Docker gateway обойти gos_router.
ip route replace "$internal_subnet" via "$router_external_ip"

# Docker restart сохраняет runtime-файлы writable layer. Удаляем PID-файлы
# завершившихся XRDP-процессов, чтобы evil-машина могла корректно перезапуститься.
rm -f /run/xrdp/xrdp.pid /run/xrdp/xrdp-sesman.pid

/usr/sbin/sshd
/usr/sbin/xrdp-sesman
exec /usr/sbin/xrdp --nodaemon
