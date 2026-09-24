# GOSservice Lab

Лаборатория разделена на внутреннюю и внешнюю Docker-сети. Единственный
маршрут между ними проходит через `gos_router`.

```text
gos_arm_evil (172.28.8.10)
        |
external_net (172.28.8.0/24)
        |
gos_router (172.28.8.254 / 10.10.20.254)
        |
internal_net (10.10.20.0/24)
        +-- gos_arm_adm
        +-- gos_dns  (10.10.20.53)
        +-- gos_web  (10.10.20.20)
        +-- gos_mail (10.10.20.40)
```

Роутер разрешает внешней машине только следующие новые соединения:

- HTTP к `site.gos.local:80`;
- DNS к `dns.gos.local:53` по TCP и UDP;
- SMTP к `mail.gos.local:25`;
- IMAP к `mail.gos.local:143`;
- SMTP submission к `mail.gos.local:587`.

Остальной трафик из `external_net` во внутреннюю сеть блокируется. Suricata
пассивно наблюдает внешний интерфейс и не блокирует трафик.

## Запуск

Ubuntu VM:

```bash
cp .env.example .env
# измените демонстрационные пароли и при необходимости host-порты
make up
```

macOS:

```bash
cp .env.example .env
# измените демонстрационные пароли и при необходимости host-порты
make up-local
```

Перед запуском Makefile проверяет занятость всех опубликованных портов и
пересечение `GOS_EXTERNAL_SUBNET` с существующими Docker-сетями. Проверки можно
выполнить отдельно:

```bash
make check-ports
make check-network
```

Если `.env` уже существовал до добавления учебного сайта, замените
`ESPOCRM_HTTP_HOST_PORT` на `WEBSITE_HTTP_HOST_PORT=8088`. Для более старых
конфигураций также перенесите новые
`EVIL_*`, `GOS_ARM_EVIL_IP`, `GOS_ROUTER_INTERNAL_IP` и
`GOS_ROUTER_EXTERNAL_IP` из `.env.example`, замените `GOS_EXTERNAL_SUBNET` на
`172.28.8.0/24` и удалите устаревший `GOS_WEB_EXTERNAL_IP`. Команда `make env`
не перезаписывает существующий файл и сохранит локальные пароли.

Старая сеть `gos_external_net` могла остаться с диапазоном `10.10.30.0/24`.
В этом случае `make check-network` остановит запуск. Остановите текущий Compose
обычной командой `docker compose ... down` без `-v`, чтобы сохранить volumes,
и затем повторите `make up` или `make up-local`: сеть будет создана заново уже
как `172.28.8.0/24`.

## Доступ

Актуальные RDP/SSH-адреса печатает:

```bash
make rdp-info
```

Основные команды:

```bash
make ssh-adm
make ssh-user
make ssh-evil
make ssh-router
make ssh-web
make shell-router
make shell-web
make suricata-alerts
```

SSH роутера не публикуется на MacBook или Ubuntu VM. `make ssh-router`
запускает SSH-клиент внутри `gos_arm_adm` и подключается к
`admin@router.gos.local` (имя пользователя фактически берется из
`LOCALADMIN_USER`).

События Suricata хранятся в persistent volume `suricata_logs`:

```bash
make suricata-alerts
docker compose --env-file .env -f docker-compose.yml \
  exec gos_router tail -f /var/log/suricata/eve.json
```

## Учебный сайт nginx

`gos_web` открывает учебный сайт по `http://site.gos.local` внутри стенда и
через роутер с evil-машины. С host сайт доступен на
`http://127.0.0.1:${WEBSITE_HTTP_HOST_PORT}` после `make up-local` или на
`http://<VM_IP>:${WEBSITE_HTTP_HOST_PORT}` после `make up`.

EspoCRM 10.0.1 не публикуется как отдельный интерфейс: ее CLI-инсталлятор
внутри `gos_web` создает полную схему БД, после чего `gos_db_seed` заполняет
таблицу `contact` 51 тестовой записью. Nginx обслуживает только файлы из
`/var/www/html`.

Исходный учебный сценарий намеренно содержит разные проверки пароля:

- форма отправляет `admin / xxXX1234!` на `/users.php`;
- `users.php` ожидает `admin / admin`;
- `users_pass.php` ожидает `admin / xxXX1234!`.

Студент подключается по SSH с adm-машины (`make ssh-web`) и добавляет в
`/etc/nginx/nginx.conf`:

```nginx
location = /users.php {
    rewrite ^ /users_pass.php last;
}
```

После проверки конфигурации ее можно применить:

```bash
sudo nginx -t
sudo nginx -s reload
```

Binary и конфигурация nginx хранятся в volume `website_nginx`, поэтому
обновление и rewrite переживают restart/down/up. Полная очистка volumes
возвращает nginx 1.30.0 и исходный конфиг без rewrite.

### Обновление nginx без перезапуска контейнера

Nginx работает в daemon-режиме, а PID 1 контейнера принадлежит SSHD. Поэтому
студент может вручную заменить бинарник и переключить master-процессы без
перезапуска `gos_web`. Например, для обновления до 1.30.2:

```bash
NEW_NGINX_VERSION=1.30.2
cd "$HOME"
curl -fLO "https://nginx.org/download/nginx-${NEW_NGINX_VERSION}.tar.gz"
tar -xzf "nginx-${NEW_NGINX_VERSION}.tar.gz"
cd "nginx-${NEW_NGINX_VERSION}"

./configure \
  --prefix=/opt/website-nginx \
  --sbin-path=/opt/website-nginx/sbin/nginx \
  --conf-path=/opt/website-nginx/conf/nginx.conf \
  --pid-path=/run/nginx.pid \
  --lock-path=/run/nginx.lock \
  --error-log-path=/var/log/nginx/error.log \
  --http-log-path=/var/log/nginx/access.log \
  --with-http_ssl_module \
  --with-http_v2_module \
  --with-http_gzip_static_module \
  --with-threads
make -j"$(nproc)"

./objs/nginx -V
sudo ./objs/nginx -t

OLD_NGINX_VERSION="$(nginx -v 2>&1 | cut -d/ -f2)"
sudo cp -p \
  /opt/website-nginx/sbin/nginx \
  "/opt/website-nginx/sbin/nginx.${OLD_NGINX_VERSION}.bak"
sudo install -o root -g root -m 0755 \
  ./objs/nginx \
  /opt/website-nginx/sbin/nginx.new
sudo mv \
  /opt/website-nginx/sbin/nginx.new \
  /opt/website-nginx/sbin/nginx

OLD_MASTER="$(cat /run/nginx.pid)"
sudo kill -USR2 "$OLD_MASTER"

for attempt in $(seq 1 20); do
  if [ -s /run/nginx.pid ] \
    && [ -s /run/nginx.pid.oldbin ] \
    && [ "$(cat /run/nginx.pid)" != "$OLD_MASTER" ]; then
    break
  fi
  sleep 1
done

NEW_MASTER="$(cat /run/nginx.pid)"
test "$NEW_MASTER" != "$OLD_MASTER"
test "$(cat /run/nginx.pid.oldbin)" = "$OLD_MASTER"
ps -o pid,ppid,user,args -p "$OLD_MASTER,$NEW_MASTER"

sudo kill -WINCH "$OLD_MASTER"
curl -fsSI http://127.0.0.1/index.html
nginx -v

sudo kill -QUIT "$OLD_MASTER"

for attempt in $(seq 1 20); do
  ! kill -0 "$OLD_MASTER" 2>/dev/null && break
  sleep 1
done

test ! -e /run/nginx.pid.oldbin
ps -o pid,ppid,user,args -p "$NEW_MASTER"
curl -fsSI http://127.0.0.1/index.html
```

Важно: `WINCH` и финальный `QUIT` отправляются старому master из
`/run/nginx.pid.oldbin`, а не новому процессу из `/run/nginx.pid`.

Если проверка после `WINCH` не прошла, до финального `QUIT` можно вернуть
старые worker-процессы и бинарник:

```bash
sudo install -o root -g root -m 0755 \
  "/opt/website-nginx/sbin/nginx.${OLD_NGINX_VERSION}.bak" \
  /opt/website-nginx/sbin/nginx.rollback
sudo mv \
  /opt/website-nginx/sbin/nginx.rollback \
  /opt/website-nginx/sbin/nginx
sudo kill -HUP "$OLD_MASTER"
sudo kill -QUIT "$NEW_MASTER"
```

## Учебные правила iptables на роутере

Пользователь `LOCALADMIN_USER` имеет sudo-доступ и может менять полный IPv4
ruleset обычными командами `iptables`. Например, чтобы запретить evil-машине
SMTP submission:

```bash
ssh admin@router.gos.local
sudo iptables -I FORWARD 1 \
  -s 172.28.8.10 -d 10.10.20.40 -p tcp --dport 587 -j REJECT
sudo iptables -L -n -v --line-numbers
```

DNS с evil-машины изначально доступен по TCP и UDP. Проверить его можно так:

```bash
nmap -sT -p 53 dns.gos.local
sudo nmap -sU -p 53 dns.gos.local
dig @dns.gos.local site.gos.local +short
```

Чтобы закрыть DNS на роутере, студент блокирует оба протокола в `FORWARD`:

```bash
sudo iptables -I FORWARD 1 \
  -s 172.28.8.10 -d 10.10.20.53 -p tcp --dport 53 -j REJECT
sudo iptables -I FORWARD 1 \
  -s 172.28.8.10 -d 10.10.20.53 -p udp --dport 53 -j REJECT
sudo iptables -L FORWARD -n -v --line-numbers
```

Текущий ruleset автоматически сохраняется при корректной остановке роутера в
volume `router_firewall_state`. Поэтому изменения переживают `restart`,
`docker compose down/up` и пересоздание контейнера без удаления volumes:

```bash
make router-firewall
make restart-router
```

Студент может правилами `INPUT` или `OUTPUT` заблокировать собственное
SSH-подключение, а правилами `FORWARD` — нарушить маршрутизацию между сетями.
Штатный сброс выполняется только вместе с полной очисткой данных стенда:

```bash
make clean-volumes
make up
```

Для очистки также образов и оставшихся ресурсов используется
`CONFIRM=1 make clean-all`. Проброшенные на host порты из
`docker-compose.local.yml` и `docker-compose.vm.yml` не проходят через
`gos_router`; его `iptables` управляет трафиком между `external_net` и
`internal_net`.

## Wazuh

Три Wazuh-пароля в `.env.example` соответствуют tracked-конфигурации и bcrypt
hashes. При их смене нужно синхронно обновить настройки indexer и dashboard.
Suricata в этой итерации хранит события локально и не отправляет их в Wazuh.

Прямой Compose-запуск для Ubuntu VM остается доступен:

```bash
docker compose --env-file .env -f docker-compose.yml -f docker-compose.vm.yml up -d --build
```
