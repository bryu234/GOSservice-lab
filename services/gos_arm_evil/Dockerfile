ARG UBUNTU_VERSION=24.04
FROM ubuntu:${UBUNTU_VERSION}

USER root

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=Etc/UTC \
    LANG=en_US.UTF-8

# Внешняя рабочая станция повторяет hardened desktop-подход gos_arm_adm,
# но использует отдельную учетную запись EVIL_USERNAME.
RUN apt-get update && \
    echo "wireshark-common wireshark-common/install-setuid boolean false" | debconf-set-selections && \
    apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      dbus-x11 \
      iproute2 \
      iputils-ping \
      locales \
      lsb-release \
      nano \
      net-tools \
      netcat-openbsd \
      nmap \
      openssh-client \
      openssh-server \
      procps \
      software-properties-common \
      sudo \
      tshark \
      vim \
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

RUN if id ubuntu >/dev/null 2>&1; then userdel --remove ubuntu; fi

COPY start.sh /usr/local/bin/gos-arm-evil-start
RUN chmod +x /usr/local/bin/gos-arm-evil-start

EXPOSE 22 3389

ENTRYPOINT ["/usr/local/bin/gos-arm-evil-start"]
