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

# Пользовательская рабочая станция собирается напрямую из официального Ubuntu.
# В образе нет заранее созданных interactive-пользователей.
FROM ubuntu:${UBUNTU_VERSION}

# Все настройки контейнера выполняются от root, чтобы можно было ставить пакеты
# и настраивать SSH-сервис.
USER root

# Сохраняем timezone и locale прежнего desktop-образа.
ENV DEBIAN_FRONTEND=noninteractive \
    TZ=Etc/UTC \
    LANG=en_US.UTF-8

# Воспроизводим desktop-слой прежнего образа: XFCE, XRDP/Xorg, D-Bus,
# PulseAudio, Firefox, Xubuntu icons и X11 utilities.
# Дополнительно сохраняем прежний пользовательский минимум:
# - thunderbird нужен как почтовый клиент;
# - openssh-server нужен для SSH-доступа на user-машину;
# - sudo нужен только для отдельной админской учетной записи localadmin.
# Административные инструменты из adm-образа сюда намеренно не ставим.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      ca-certificates \
      dbus-x11 \
      git \
      locales \
      openssh-server \
      pavucontrol \
      pulseaudio \
      pulseaudio-utils \
      software-properties-common \
      sudo \
      vim \
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
    apt-get install -y --no-install-recommends \
      firefox \
      thunderbird && \
    rm -rf /var/lib/apt/lists/*

# Актуальный официальный ubuntu:24.04 содержит пользователя ubuntu с UID 1000.
# Удаляем его на этапе сборки: рабочие учетные записи создает только start.sh из .env.
RUN if id ubuntu >/dev/null 2>&1; then userdel --remove ubuntu; fi

# Добавляем только собранные PulseAudio-модули XRDP, без toolchain builder-stage.
COPY --from=pulseaudio-builder /tmp/install /
RUN sed -i 's|^Exec=.*|Exec=/usr/bin/pulseaudio|' /etc/xdg/autostart/pulseaudio-xrdp.desktop

# Существующий entrypoint user-машины остается без изменений.
# Он создает обычного пользователя, запускает SSH и напрямую запускает XRDP.
COPY start.sh /usr/local/bin/gos-arm-user-start
RUN chmod +x /usr/local/bin/gos-arm-user-start

# 22 - SSH внутри контейнера, 3389 - XRDP внутри контейнера.
# Наружные host-порты задаются в .env и пробрасываются через compose override.
EXPOSE 22 3389

# Запускаем подготовительный скрипт user-машины.
ENTRYPOINT ["/usr/local/bin/gos-arm-user-start"]
