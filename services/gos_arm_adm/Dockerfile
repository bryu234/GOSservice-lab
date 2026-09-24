ARG UBUNTU_VERSION=24.04

# Административная рабочая станция собирается напрямую из официального Ubuntu.
# В образе нет заранее созданных interactive-пользователей.
FROM ubuntu:${UBUNTU_VERSION}

# Все настройки контейнера выполняются от root, чтобы можно было ставить пакеты
# и настраивать системные сервисы.
USER root

# Сохраняем timezone и locale прежнего desktop-образа.
ENV DEBIAN_FRONTEND=noninteractive \
    TZ=Etc/UTC \
    LANG=en_US.UTF-8

# Воспроизводим desktop-слой: XFCE, XRDP/Xorg, D-Bus, Firefox,
# Xubuntu icons и X11 utilities.
# Дополнительно сохраняем прежний набор инструментов администратора:
# - openssh-server нужен для SSH-доступа на adm;
# - dnsutils/curl/nmap/net-tools/iproute2 нужны для сетевой диагностики;
# - wireshark/tshark нужны для анализа трафика в лабораторной;
# - rsyslog оставлен для базового системного логирования.
RUN apt-get update && \
    echo "wireshark-common wireshark-common/install-setuid boolean false" | debconf-set-selections && \
    apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      dbus-x11 \
      dnsutils \
      git \
      iproute2 \
      iputils-ping \
      locales \
      lsb-release \
      nano \
      net-tools \
      nmap \
      openssh-client \
      openssh-server \
      rsyslog \
      software-properties-common \
      sudo \
      tshark \
      vim \
      wget \
      wireshark \
      x11-xserver-utils \
      xfce4 \
      xfce4-goodies \
      xorgxrdp \
      xrdp \
      xubuntu-icon-theme && \
    locale-gen en_US.UTF-8 && \
    add-apt-repository -y ppa:mozillateam/ppa && \
    printf '%s\n' \
      'Package: *' \
      'Pin: release o=LP-PPA-mozillateam' \
      'Pin-Priority: 1001' \
      >/etc/apt/preferences.d/mozilla-firefox && \
    apt-get update && \
    apt-get install -y --no-install-recommends firefox && \
    rm -rf /var/lib/apt/lists/*

# Актуальный официальный ubuntu:24.04 содержит пользователя ubuntu с UID 1000.
# Удаляем его на этапе сборки: рабочие учетные записи создает только start.sh из .env.
RUN if id ubuntu >/dev/null 2>&1; then userdel --remove ubuntu; fi

# Существующий entrypoint без изменений создает локального администратора,
# запускает SSH и напрямую запускает XRDP.
COPY start.sh /usr/local/bin/gos-arm-adm-start
RUN chmod +x /usr/local/bin/gos-arm-adm-start

# 22 - SSH внутри контейнера, 3389 - XRDP внутри контейнера.
# Наружные host-порты задаются в .env и пробрасываются через compose override.
EXPOSE 22 3389

# Запускаем подготовительный скрипт adm-машины.
ENTRYPOINT ["/usr/local/bin/gos-arm-adm-start"]
