FROM ubuntu:24.04

# Отключаем интерактивные вопросы apt/postfix во время сборки образа.
ENV DEBIAN_FRONTEND=noninteractive

# Устанавливаем классический почтовый стек:
# - postfix принимает и доставляет SMTP-почту;
# - dovecot отдает почтовый ящик по IMAP;
# - openssh-server/sudo/nano нужны для администрирования с adm-машины;
# - netcat-openbsd используется healthcheck'ом compose;
# - rsyslog установлен, но логирование Postfix включает студент.
RUN set -eux; \
    echo "postfix postfix/mailname string gos.local" | debconf-set-selections; \
    echo "postfix postfix/main_mailer_type select Internet Site" | debconf-set-selections; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      ca-certificates \
      dovecot-core \
      dovecot-imapd \
      dovecot-lmtpd \
      iproute2 \
      lsb-release \
      netcat-openbsd \
      nano \
      openssh-server \
      postfix \
      procps \
      rsyslog \
      sudo; \
    rm -rf /var/lib/apt/lists/*

# Скрипт создает начальные конфиги один раз и затем сохраняет изменения студента.
COPY start.sh /usr/local/bin/start.sh
RUN chmod +x /usr/local/bin/start.sh

# SSH, SMTP, IMAP и SMTP submission доступны только внутри docker-сети.
EXPOSE 22 25 143 587

CMD ["/usr/local/bin/start.sh"]
