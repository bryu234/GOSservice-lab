# Пользовательская рабочая станция стенда.
# Базовый образ уже содержит графическое окружение и XRDP для подключения по RDP.
FROM scottyhardy/docker-remote-desktop:latest

# Все настройки контейнера выполняются от root, чтобы можно было ставить пакеты
# и настраивать SSH-сервис.
USER root

# Отключаем интерактивные prompts apt/dpkg и фиксируем timezone внутри контейнера.
ENV DEBIAN_FRONTEND=noninteractive TZ=Etc/UTC

# Устанавливаем только пользовательский минимум:
# - thunderbird нужен как почтовый клиент;
# - openssh-server нужен для SSH-доступа на user-машину;
# - sudo нужен только для отдельной админской учетной записи localadmin.
# Административные инструменты из adm-образа сюда намеренно не ставим.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      openssh-server \
      sudo \
      thunderbird && \
    rm -rf /var/lib/apt/lists/*

# Копируем отдельный entrypoint user-машины.
# Он создает обычного пользователя, запускает SSH и передает управление XRDP.
COPY start.sh /usr/local/bin/gos-arm-user-start
RUN chmod +x /usr/local/bin/gos-arm-user-start

# 22 - SSH внутри контейнера, 3389 - XRDP внутри контейнера.
# Наружные host-порты задаются в .env и пробрасываются через compose override.
EXPOSE 22 3389

# Запускаем подготовительный скрипт user-машины.
ENTRYPOINT ["/usr/local/bin/gos-arm-user-start"]
