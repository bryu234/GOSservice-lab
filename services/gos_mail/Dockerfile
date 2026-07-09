FROM ubuntu:24.04

# Отключаем интерактивные вопросы apt/postfix во время сборки образа.
ENV DEBIAN_FRONTEND=noninteractive

# Устанавливаем классический почтовый стек:
# - postfix принимает и доставляет SMTP-почту;
# - dovecot отдает почтовый ящик по IMAP;
# - netcat-openbsd используется healthcheck'ом compose.
# Логирование почты в /var/log/mail.log намеренно не включаем для лабораторной.
RUN set -eux; \
    echo "postfix postfix/mailname string gos.local" | debconf-set-selections; \
    echo "postfix postfix/main_mailer_type select Internet Site" | debconf-set-selections; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      ca-certificates \
      dovecot-core \
      dovecot-imapd \
      dovecot-lmtpd \
      netcat-openbsd \
      postfix \
      procps; \
    rm -rf /var/lib/apt/lists/*

# Скрипт на каждом старте генерирует конфиги из .env и создает mailbox.
COPY start.sh /usr/local/bin/start.sh
RUN chmod +x /usr/local/bin/start.sh

# SMTP, IMAP и SMTP submission доступны только внутри docker-сети.
EXPOSE 25 143 587

CMD ["/usr/local/bin/start.sh"]
