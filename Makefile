# По умолчанию Makefile читает переменные стенда из .env.
ENV_FILE ?= .env

# Локальный профиль: порты пробрасываются только на 127.0.0.1.
COMPOSE_LOCAL = docker compose --env-file $(ENV_FILE) -f docker-compose.yml -f docker-compose.local.yml

# VM-профиль: порты пробрасываются на 0.0.0.0.
COMPOSE_VM = docker compose --env-file $(ENV_FILE) -f docker-compose.yml -f docker-compose.vm.yml

# Фиксированные имена контейнеров стенда. Нужны для fallback-очистки,
# если на сервере была развернута старая или неправильная версия compose.
PROJECT_CONTAINERS = gos_arm_adm gos_arm_user gos_dns gos_web gos_db

# Имена сетей текущей версии и старых вариантов стенда.
# Удаление сетей выполняется после остановки контейнеров.
PROJECT_NETWORKS = gos_internal_net gos_external_net gos_admin_net gos_servers_net

# Имена локально собранных compose-образов проекта.
# Pull-образы также удаляются через docker compose down --rmi all.
PROJECT_IMAGES = gosservice_lab-gos_arm_adm gosservice_lab-gos_arm_user gosservice_lab-gos_dns

# Имена named volumes при стандартном COMPOSE_PROJECT_NAME=gosservice_lab.
PROJECT_VOLUMES = gosservice_lab_espocrm_data gosservice_lab_espocrm_custom gosservice_lab_espocrm_client_custom gosservice_lab_espocrm_db

.PHONY: help env check-ports config build up up-vm down ps logs restart shell-adm shell-user ssh-adm ssh-user rdp-info clean-volumes clean-all

# Справка по основным командам управления стендом.
help:
	@echo "GOSservice Docker lab"
	@echo ""
	@echo "Setup:"
	@echo "  make env          Create .env from .env.example when missing"
	@echo "  make check-ports  Validate host ports from .env before startup"
	@echo ""
	@echo "Run locally on MacBook:"
	@echo "  make up           Start with ports bound to 127.0.0.1"
	@echo "  make down         Stop containers"
	@echo "  make logs         Follow logs"
	@echo ""
	@echo "Run on Ubuntu VM:"
	@echo "  make up-vm        Start with ports bound to 0.0.0.0"
	@echo ""
	@echo "Access:"
	@echo "  make ssh-adm      SSH into gos_arm_adm through the configured host port"
	@echo "  make ssh-user     SSH into gos_arm_user through the configured host port"
	@echo "  make rdp-info     Print RDP connection details"
	@echo ""
	@echo "Dangerous cleanup:"
	@echo "  CONFIRM=1 make clean-all  Delete lab containers, networks, volumes and images"

# Создает локальный .env из .env.example, если его еще нет.
# Существующий .env не перезаписывается, чтобы не потерять локальные пароли/порты.
env:
	@if [ ! -f "$(ENV_FILE)" ]; then \
		cp .env.example "$(ENV_FILE)"; \
		echo "Created $(ENV_FILE). Edit passwords and ports before exposing the lab."; \
	else \
		echo "$(ENV_FILE) already exists."; \
	fi

# Проверяет, что host-порты из .env свободны до запуска compose.
# Это важно для локальной разработки: RDP/SSH/HTTP порты могут быть уже заняты.
check-ports: env
	@set -a; . ./$(ENV_FILE); set +a; \
	for item in "ADM_RDP_HOST_PORT:adm RDP" "ADM_SSH_HOST_PORT:adm SSH" "USER_RDP_HOST_PORT:user RDP" "USER_SSH_HOST_PORT:user SSH" "ESPOCRM_HTTP_HOST_PORT:EspoCRM HTTP"; do \
		var=$${item%%:*}; label=$${item#*:}; eval port=\$$$${var}; \
		case "$$port" in ""|*[!0-9]*) echo "$$label port '$$port' is invalid. Check $$var in $(ENV_FILE)."; exit 1 ;; esac; \
		if lsof -nP -iTCP:$$port -sTCP:LISTEN >/dev/null 2>&1; then \
			echo "$$label host port $$port is busy. Change $$var in $(ENV_FILE)."; \
			lsof -nP -iTCP:$$port -sTCP:LISTEN; \
			exit 1; \
		fi; \
		echo "$$label host port $$port is free."; \
	done

# Печатает итоговую compose-конфигурацию после подстановки .env и override.
config: env
	@$(COMPOSE_LOCAL) config

# Собирает кастомные образы adm и dns.
build: env
	@$(COMPOSE_LOCAL) build

# Запускает стенд на MacBook: перед стартом проверяет занятость портов.
up: check-ports
	@$(COMPOSE_LOCAL) up -d --build
	@$(MAKE) rdp-info

# Запускает стенд на Ubuntu VM: порты будут доступны на всех интерфейсах VM.
up-vm: check-ports
	@$(COMPOSE_VM) up -d --build
	@$(MAKE) rdp-info

# Останавливает контейнеры, но сохраняет volumes с данными EspoCRM/MariaDB.
down: env
	@$(COMPOSE_LOCAL) down

# Показывает состояние контейнеров.
ps: env
	@$(COMPOSE_LOCAL) ps

# Показывает последние логи и продолжает следить за ними.
logs: env
	@$(COMPOSE_LOCAL) logs -f --tail=100

# Полный перезапуск без удаления volumes.
restart: down up

# Открывает shell внутри adm-контейнера.
shell-adm: env
	@$(COMPOSE_LOCAL) exec gos_arm_adm bash

# Открывает shell внутри пользовательской машины.
shell-user: env
	@$(COMPOSE_LOCAL) exec gos_arm_user bash

# Подключается к adm по SSH через host-порт из .env.
ssh-adm: env
	@set -a; . ./$(ENV_FILE); set +a; \
	ssh -p "$$ADM_SSH_HOST_PORT" "$$LOCALADMIN_USER@127.0.0.1"

# Подключается к user-машине по SSH через host-порт из .env.
ssh-user: env
	@set -a; . ./$(ENV_FILE); set +a; \
	ssh -p "$$USER_SSH_HOST_PORT" "$$USER_USERNAME@127.0.0.1"

# Печатает актуальные параметры подключения из .env.
rdp-info: env
	@set -a; . ./$(ENV_FILE); set +a; \
	echo "adm RDP: 127.0.0.1:$$ADM_RDP_HOST_PORT"; \
	echo "adm SSH: ssh -p $$ADM_SSH_HOST_PORT $$LOCALADMIN_USER@127.0.0.1"; \
	echo "user RDP: 127.0.0.1:$$USER_RDP_HOST_PORT"; \
	echo "user SSH: ssh -p $$USER_SSH_HOST_PORT $$USER_USERNAME@127.0.0.1"; \
	echo "EspoCRM from host: http://127.0.0.1:$$ESPOCRM_HTTP_HOST_PORT with Host header crm.$$GOS_DOMAIN"

# Полностью удаляет контейнеры и volumes.
# Использовать только когда нужно сбросить EspoCRM/MariaDB до чистого состояния.
clean-volumes: env
	@$(COMPOSE_LOCAL) down -v

# Полностью удаляет все Docker-ресурсы этого стенда.
# Команда опасная: удаляет контейнеры, сети, volumes с данными и образы.
# Защита CONFIRM=1 нужна, чтобы случайно не стереть лабораторную БД.
clean-all: env
	@if [ "$(CONFIRM)" != "1" ]; then \
		echo "This command deletes Docker resources created for the lab."; \
		echo "It removes containers, networks, volumes and images."; \
		echo "Run it explicitly: CONFIRM=1 make clean-all"; \
		exit 1; \
	fi
	@echo "Stopping compose stack and deleting compose volumes, networks, orphans and images..."
	@$(COMPOSE_LOCAL) down --volumes --remove-orphans --rmi all || true
	@echo "Deleting fixed-name lab containers left by old deployments..."
	@docker rm -f $(PROJECT_CONTAINERS) >/dev/null 2>&1 || true
	@echo "Deleting lab networks left by current or legacy compose files..."
	@docker network rm $(PROJECT_NETWORKS) >/dev/null 2>&1 || true
	@echo "Deleting standard lab volumes left by current compose project name..."
	@docker volume rm $(PROJECT_VOLUMES) >/dev/null 2>&1 || true
	@echo "Deleting locally built lab images left by compose..."
	@docker image rm $(PROJECT_IMAGES) >/dev/null 2>&1 || true
	@echo "Lab Docker cleanup completed."
