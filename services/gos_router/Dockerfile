FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=Etc/UTC

# Роутер остается обычной Ubuntu-машиной стенда: SSH для внутреннего
# администрирования, iptables/iproute2 для маршрутизации и Suricata как IDS.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      iproute2 \
      iptables \
      lsb-release \
      nano \
      netcat-openbsd \
      openssh-server \
      procps \
      rsyslog \
      sudo \
      suricata \
      wget && \
    rm -rf /var/lib/apt/lists/*

COPY rules/gos-local.rules /etc/suricata/rules/gos-local.rules
COPY start.sh /usr/local/bin/gos-router-start
RUN chmod +x /usr/local/bin/gos-router-start

# SSH доступен только на внутреннем интерфейсе; наружу host-порт не публикуется.
EXPOSE 22

ENTRYPOINT ["/usr/local/bin/gos-router-start"]
