# Базовый образ уже содержит графическое окружение и XRDP для подключения по RDP.
FROM scottyhardy/docker-remote-desktop:latest

# Все настройки контейнера выполняются от root, чтобы можно было ставить пакеты
# и настраивать системные сервисы.
USER root

# Отключаем интерактивные prompts apt/dpkg и фиксируем timezone внутри контейнера.
ENV DEBIAN_FRONTEND=noninteractive TZ=Etc/UTC

# Устанавливаем инструменты администратора:
# - openssh-server нужен для SSH-доступа на adm;
# - dnsutils/curl/nmap/net-tools/iproute2 нужны для сетевой диагностики;
# - wireshark/tshark нужны для анализа трафика в лабораторной;
# - rsyslog оставлен для базового системного логирования.
RUN apt-get update && \
    echo "wireshark-common wireshark-common/install-setuid boolean false" | debconf-set-selections && \
    apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      dnsutils \
      iproute2 \
      iputils-ping \
      nano \
      net-tools \
      nmap \
      openssh-client \
      openssh-server \
      rsyslog \
      sudo \
      tshark \
      wireshark && \
    rm -rf /var/lib/apt/lists/*

# Копируем наш entrypoint, который создает локального администратора
# и запускает SSH перед стартом штатного RDP entrypoint базового образа.
COPY start.sh /usr/local/bin/gos-arm-adm-start
RUN chmod +x /usr/local/bin/gos-arm-adm-start

# 22 - SSH внутри контейнера, 3389 - XRDP внутри контейнера.
# Наружные host-порты задаются в .env и пробрасываются через compose override.
EXPOSE 22 3389

# Запускаем подготовительный скрипт adm-машины.
ENTRYPOINT ["/usr/local/bin/gos-arm-adm-start"]
