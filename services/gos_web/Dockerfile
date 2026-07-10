# Web-машина стенда: Ubuntu + nginx 1.30.0 + PHP-FPM + EspoCRM.
# Nginx собирается из официального исходного архива, чтобы версия была
# жестко зафиксирована для учебного задания по обновлению nginx.
FROM ubuntu:24.04

ARG NGINX_VERSION=1.30.0
ARG ESPOCRM_VERSION=10.0.1

ENV DEBIAN_FRONTEND=noninteractive
ENV NGINX_VERSION=${NGINX_VERSION}
ENV ESPOCRM_VERSION=${ESPOCRM_VERSION}

# Системные пакеты:
# - build-essential/libpcre/zlib/ssl нужны для сборки nginx;
# - PHP-FPM и расширения нужны EspoCRM;
# - mariadb-client нужен health/startup-проверкам доступа к gos_db;
# - openssh-server/sudo/nano нужны для администрирования с adm-машины.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        build-essential \
        libpcre3-dev \
        zlib1g-dev \
        libssl-dev \
        unzip \
        mariadb-client \
        nano \
        openssh-server \
        php8.3-cli \
        php8.3-fpm \
        php8.3-mysql \
        php8.3-curl \
        php8.3-gd \
        php8.3-imap \
        php8.3-intl \
        php8.3-ldap \
        php8.3-mbstring \
        php8.3-xml \
        php8.3-zip \
        php8.3-bcmath \
        sudo \
    && rm -rf /var/lib/apt/lists/*

# Сборка nginx нужной версии из официального tar.gz.
# Prefix /usr/local/nginx оставляет nginx отдельно от пакетной системы Ubuntu.
RUN curl -fsSL "https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz" -o /tmp/nginx.tar.gz \
    && mkdir -p /tmp/nginx-src \
    && tar -xzf /tmp/nginx.tar.gz -C /tmp/nginx-src --strip-components=1 \
    && cd /tmp/nginx-src \
    && ./configure \
        --prefix=/usr/local/nginx \
        --sbin-path=/usr/local/sbin/nginx \
        --conf-path=/etc/nginx/nginx.conf \
        --pid-path=/run/nginx.pid \
        --lock-path=/run/nginx.lock \
        --error-log-path=/var/log/nginx/error.log \
        --http-log-path=/var/log/nginx/access.log \
        --with-http_ssl_module \
        --with-http_v2_module \
        --with-http_gzip_static_module \
        --with-threads \
    && make -j"$(nproc)" \
    && make install \
    && rm -rf /tmp/nginx.tar.gz /tmp/nginx-src \
    && mkdir -p /var/cache/nginx /var/log/nginx /run/php

# Устанавливаем EspoCRM из официального релизного ZIP в /var/www/espocrm.
# Файлы приложения лежат внутри образа, а изменяемые каталоги подключаются volumes.
RUN curl -fsSL "https://www.espocrm.com/downloads/EspoCRM-${ESPOCRM_VERSION}.zip" -o /tmp/espocrm.zip \
    && mkdir -p /var/www \
    && unzip -q /tmp/espocrm.zip -d /var/www \
    && mv "/var/www/EspoCRM-${ESPOCRM_VERSION}" /var/www/espocrm \
    && rm -f /tmp/espocrm.zip \
    && chown -R www-data:www-data /var/www/espocrm

# Конфигурация PHP-FPM: слушаем локальный TCP-порт, чтобы nginx-конфиг был проще.
RUN sed -i 's|^listen = .*|listen = 127.0.0.1:9000|' /etc/php/8.3/fpm/pool.d/www.conf \
    && sed -i 's|^;clear_env = no|clear_env = no|' /etc/php/8.3/fpm/pool.d/www.conf \
    && sed -i 's|^upload_max_filesize = .*|upload_max_filesize = 50M|' /etc/php/8.3/fpm/php.ini \
    && sed -i 's|^post_max_size = .*|post_max_size = 50M|' /etc/php/8.3/fpm/php.ini \
    && sed -i 's|^memory_limit = .*|memory_limit = 256M|' /etc/php/8.3/fpm/php.ini

COPY nginx.conf /etc/nginx/nginx.conf
COPY start.sh /usr/local/bin/gos-web-start.sh

RUN chmod +x /usr/local/bin/gos-web-start.sh

WORKDIR /var/www/espocrm

# SSH и HTTP доступны только через docker-сети/compose-публикацию.
EXPOSE 22 80

CMD ["/usr/local/bin/gos-web-start.sh"]
