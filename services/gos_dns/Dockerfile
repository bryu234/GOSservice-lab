# Минимальный Ubuntu-образ для DNS-сервера лабораторной.
FROM ubuntu:22.04

# Отключаем интерактивные prompts apt/dpkg и фиксируем timezone внутри контейнера.
ENV DEBIAN_FRONTEND=noninteractive TZ=Etc/UTC

# Устанавливаем Bind9 как DNS-сервер, dnsutils для healthcheck/диагностики
# и rsyslog для базового логирования.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      bind9 \
      bind9utils \
      dnsutils \
      iputils-ping \
      nano \
      rsyslog && \
    rm -rf /var/lib/apt/lists/*

# Скрипт на старте генерирует named.conf и зону gos.local из переменных .env.
COPY start.sh /usr/local/bin/gos-dns-start
RUN chmod +x /usr/local/bin/gos-dns-start

# DNS слушает TCP/UDP 53 внутри docker-сети.
EXPOSE 53/tcp 53/udp

# Запускаем генерацию конфигов и named.
CMD ["/usr/local/bin/gos-dns-start"]
