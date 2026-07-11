# Сборка PulseAudio-модулей XRDP в отдельном stage,
# чтобы не оставлять compiler и build dependencies в итоговом desktop-образе.
ARG UBUNTU_VERSION=24.04
FROM ubuntu:${UBUNTU_VERSION} AS pulseaudio-builder

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      autoconf \
      build-essential \
      ca-certificates \
      dpkg-dev \
      git \
      libltdl-dev \
      libpulse-dev \
      libtool \
      lsb-release \
      sudo && \
    rm -rf /var/lib/apt/lists/*

RUN git clone https://github.com/neutrinolabs/pulseaudio-module-xrdp.git /pulseaudio-module-xrdp
WORKDIR /pulseaudio-module-xrdp
RUN scripts/install_pulseaudio_sources_apt.sh && \
    ./bootstrap && \
    ./configure PULSE_DIR=/root/pulseaudio.src && \
    make -j"$(nproc)" && \
    make install DESTDIR=/tmp/install

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

# Воспроизводим desktop-слой прежнего образа: XFCE, XRDP/Xorg, D-Bus,
# PulseAudio, Firefox, Xubuntu icons и X11 utilities.
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
      nano \
      net-tools \
      nmap \
      openssh-client \
      openssh-server \
      pavucontrol \
      pulseaudio \
      pulseaudio-utils \
      rsyslog \
      software-properties-common \
      sudo \
      tshark \
      vim \
      wireshark \
      x11-xserver-utils \
      xfce4 \
      xfce4-goodies \
      xfce4-pulseaudio-plugin \
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

# Добавляем только собранные PulseAudio-модули XRDP, без toolchain builder-stage.
COPY --from=pulseaudio-builder /tmp/install /
RUN sed -i 's|^Exec=.*|Exec=/usr/bin/pulseaudio|' /etc/xdg/autostart/pulseaudio-xrdp.desktop

# Существующий entrypoint без изменений создает локального администратора,
# запускает SSH и напрямую запускает XRDP.
COPY start.sh /usr/local/bin/gos-arm-adm-start
RUN chmod +x /usr/local/bin/gos-arm-adm-start

# 22 - SSH внутри контейнера, 3389 - XRDP внутри контейнера.
# Наружные host-порты задаются в .env и пробрасываются через compose override.
EXPOSE 22 3389

# Запускаем подготовительный скрипт adm-машины.
ENTRYPOINT ["/usr/local/bin/gos-arm-adm-start"]
