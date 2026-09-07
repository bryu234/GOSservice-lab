# Минимальный Ubuntu-образ для DNS-сервера лабораторной.
FROM ubuntu:22.04

# Отключаем интерактивные prompts apt/dpkg и фиксируем timezone внутри контейнера.
ENV DEBIAN_FRONTEND=noninteractive TZ=Etc/UTC

# Устанавливаем Bind9 как DNS-сервер, dnsutils для healthcheck/диагностики,
# SSH/sudo для администрирования с adm-машины и rsyslog для базового логирования.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      bind9 \
      bind9utils \
      curl \
      dnsutils \
      iputils-ping \
      lsb-release \
      nano \
      openssh-server \
      sudo \
      rsyslog \
      wget && \
    rm -rf /var/lib/apt/lists/*

# Каталог уже существует, поэтому студенту достаточно включить logging-блок Bind.
RUN install -d -m 0750 -o bind -g bind /var/log/bind

# Скрипт при первом старте генерирует named.conf и зону gos.local из переменных .env.
COPY start.sh /usr/local/bin/gos-dns-start
RUN chmod +x /usr/local/bin/gos-dns-start

# DNS слушает TCP/UDP 53, SSH слушает 22 только внутри docker-сети.
EXPOSE 22/tcp 53/tcp 53/udp

# Запускаем генерацию конфигов и named.
CMD ["/usr/local/bin/gos-dns-start"]
