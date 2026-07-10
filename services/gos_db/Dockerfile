# База данных EspoCRM: MariaDB + SSH/sudo для администрирования из adm-машины.
FROM mariadb:11.4

# Отключаем интерактивные prompts apt/dpkg.
ENV DEBIAN_FRONTEND=noninteractive

# openssh-server/sudo/nano нужны только для лабораторного администрирования.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      nano \
      openssh-server \
      sudo \
    && rm -rf /var/lib/apt/lists/*

# start.sh готовит SSH-админа и затем передает запуск штатному entrypoint MariaDB.
COPY start.sh /usr/local/bin/gos-db-start.sh
COPY fill_db.sh /usr/local/bin/fill_db.sh
RUN chmod +x /usr/local/bin/gos-db-start.sh /usr/local/bin/fill_db.sh

# 22 - SSH внутри стенда, 3306 - MariaDB внутри стенда.
EXPOSE 22 3306

ENTRYPOINT ["/usr/local/bin/gos-db-start.sh"]
CMD ["mariadbd"]
