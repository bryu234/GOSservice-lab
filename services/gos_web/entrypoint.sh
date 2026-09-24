#!/usr/bin/env bash
set -euo pipefail

mkdir -p /run/php /run/sshd

php_fpm="$(find /usr/sbin -name 'php-fpm*' -type f | head -n1)"
"$php_fpm" -D

# Nginx должен daemonize: только в этом режиме его master поддерживает штатный
# binary hot upgrade через USR2. Абсолютный путь нужен, чтобы старый master мог
# выполнить новый бинарник по тому же argv[0].
/opt/website-nginx/sbin/nginx

# SSHD удерживает контейнер запущенным и остается доступным студенту, пока
# daemonized nginx переключает старый и новый master-процессы.
exec /usr/sbin/sshd -D -e
