# По умолчанию Makefile читает переменные стенда из .env.
ENV_FILE ?= .env

# Базовый compose без публикации портов. Используется для одноразовых служебных задач.
COMPOSE_BASE = docker compose --env-file $(ENV_FILE) -f docker-compose.yml

# Локальный профиль: порты пробрасываются только на 127.0.0.1.
COMPOSE_LOCAL = docker compose --env-file $(ENV_FILE) -f docker-compose.yml -f docker-compose.local.yml

# VM-профиль: порты пробрасываются на 0.0.0.0.
COMPOSE_VM = docker compose --env-file $(ENV_FILE) -f docker-compose.yml -f docker-compose.vm.yml

# Основной профиль репозитория рассчитан на Ubuntu VM.
COMPOSE_DEFAULT = $(COMPOSE_VM)

# Фиксированные имена контейнеров стенда. Нужны для fallback-очистки,
# если на сервере была развернута старая или неправильная версия compose.
PROJECT_CONTAINERS = gos_arm_adm gos_arm_user gos_arm_evil gos_router gos_dns gos_mail gos_siem_certs gos_siem_manager gos_siem_indexer gos_siem_dashboard gos_web gos_db gos_db_seed

# Имена сетей текущей версии и старых вариантов стенда.
# Удаление сетей выполняется после остановки контейнеров.
PROJECT_NETWORKS = gos_internal_net gos_external_net gos_admin_net gos_servers_net

# Имена локально собранных compose-образов проекта.
# Pull-образы также удаляются через docker compose down --rmi all.
PROJECT_IMAGES = gosservice_lab-gos_arm_adm gosservice_lab-gos_arm_user gosservice_lab-gos_arm_evil gosservice_lab-gos_router gosservice_lab-gos_dns gosservice_lab-gos_mail gosservice_lab-gos_web gosservice_lab-gos_db

# Имена named volumes при стандартном COMPOSE_PROJECT_NAME=gosservice_lab.
PROJECT_VOLUMES = gosservice_lab_espocrm_data gosservice_lab_espocrm_custom gosservice_lab_espocrm_client_custom gosservice_lab_espocrm_db gosservice_lab_mail_home gosservice_lab_suricata_logs gosservice_lab_wazuh_certs gosservice_lab_wazuh_api_configuration gosservice_lab_wazuh_etc gosservice_lab_wazuh_logs gosservice_lab_wazuh_queue gosservice_lab_wazuh_var_multigroups gosservice_lab_wazuh_integrations gosservice_lab_wazuh_active_response gosservice_lab_wazuh_agentless gosservice_lab_wazuh_wodles gosservice_lab_filebeat_etc gosservice_lab_filebeat_var gosservice_lab_wazuh_indexer_data gosservice_lab_wazuh_dashboard_config gosservice_lab_wazuh_dashboard_custom

.PHONY: help env check-ports check-network check-wazuh-prereqs wazuh-certs config build up up-vm up-local fill-db fill-db-local down ps logs restart shell-adm shell-user shell-evil shell-router shell-mail shell-siem-manager shell-siem-indexer shell-siem-dashboard ssh-adm ssh-user ssh-evil ssh-router suricata-alerts rdp-info clean-volumes clean-all

# Справка по основным командам управления стендом.
help:
	@echo "GOSservice Docker lab"
	@echo ""
	@echo "Setup:"
	@echo "  make env          Create .env from .env.example when missing"
	@echo "  make wazuh-certs  Generate local Wazuh TLS certificates"
	@echo "  make check-ports  Validate host ports from .env before startup"
	@echo "  make check-network Validate the external Docker subnet before startup"
	@echo "  make fill-db      Manually refill EspoCRM contact table through the DB seed service"
	@echo ""
	@echo "Run on Ubuntu VM:"
	@echo "  make up           Start with ports bound to 0.0.0.0"
	@echo "  make up-vm        Alias for make up"
	@echo "  make down         Stop containers"
	@echo "  make logs         Follow logs"
	@echo ""
	@echo "Run locally on MacBook:"
	@echo "  make up-local     Start with ports bound to 127.0.0.1"
	@echo ""
	@echo "Access:"
	@echo "  make ssh-adm      SSH into gos_arm_adm through the configured host port"
	@echo "  make ssh-user     SSH into gos_arm_user through the configured host port"
	@echo "  make ssh-evil     SSH into gos_arm_evil through the configured host port"
	@echo "  make ssh-router   SSH from gos_arm_adm to the router's internal interface"
	@echo "  make shell-router Open a shell inside gos_router"
	@echo "  make suricata-alerts Follow Suricata fast.log on gos_router"
	@echo "  make shell-mail   Open a shell inside gos_mail"
	@echo "  make shell-siem-manager    Open a shell inside Wazuh Manager"
	@echo "  make shell-siem-indexer    Open a shell inside Wazuh Indexer"
	@echo "  make shell-siem-dashboard  Open a shell inside Wazuh Dashboard"
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
	project=$${COMPOSE_PROJECT_NAME:-gosservice_lab}; \
	for item in "ADM_RDP_HOST_PORT:adm RDP" "ADM_SSH_HOST_PORT:adm SSH" "USER_RDP_HOST_PORT:user RDP" "USER_SSH_HOST_PORT:user SSH" "EVIL_RDP_HOST_PORT:evil RDP" "EVIL_SSH_HOST_PORT:evil SSH" "ESPOCRM_HTTP_HOST_PORT:EspoCRM HTTP" "WAZUH_DASHBOARD_HOST_PORT:Wazuh Dashboard HTTPS"; do \
		var=$${item%%:*}; label=$${item#*:}; eval port=\$$$${var}; \
		case "$$port" in ""|*[!0-9]*) echo "$$label port '$$port' is invalid. Check $$var in $(ENV_FILE)."; exit 1 ;; esac; \
		if lsof -nP -iTCP:$$port -sTCP:LISTEN >/dev/null 2>&1; then \
			if docker ps --filter "label=com.docker.compose.project=$$project" --format '{{.Ports}}' 2>/dev/null | grep -q ":$$port->"; then \
				echo "$$label host port $$port is already used by this compose project."; \
				continue; \
			fi; \
			echo "$$label host port $$port is busy. Change $$var in $(ENV_FILE)."; \
			lsof -nP -iTCP:$$port -sTCP:LISTEN; \
			exit 1; \
		fi; \
		echo "$$label host port $$port is free."; \
	done

# Проверяет реальное состояние Docker IPAM, включая пересечения с более широкими /16.
check-network: env
	@set -a; . ./$(ENV_FILE); set +a; \
	python3 scripts/check_network_overlap.py "$$GOS_EXTERNAL_SUBNET" gos_external_net

# Проверяет и на Linux автоматически выставляет параметр, который нужен Wazuh Indexer/OpenSearch.
# На macOS Docker Desktop этот sysctl управляется внутри VM Docker Desktop, поэтому там пропускаем настройку.
check-wazuh-prereqs: env
	@set -a; . ./$(ENV_FILE); set +a; \
	for variable in WAZUH_INDEXER_PASSWORD WAZUH_DASHBOARD_PASSWORD WAZUH_API_PASSWORD; do \
		eval "password=\$${$${variable}}"; \
		if [ $${#password} -lt 8 ] || [ $${#password} -gt 64 ] \
			|| ! printf '%s' "$$password" | grep -q '[A-Z]' \
			|| ! printf '%s' "$$password" | grep -q '[a-z]' \
			|| ! printf '%s' "$$password" | grep -q '[0-9]' \
			|| ! printf '%s' "$$password" | grep -q '[^A-Za-z0-9]'; then \
			echo "$$variable must contain 8-64 characters, uppercase, lowercase, number and symbol."; \
			exit 1; \
		fi; \
	done; \
	if [ "$$WAZUH_INDEXER_PASSWORD" != 'GosIndexer2026!' ] \
		|| [ "$$WAZUH_DASHBOARD_PASSWORD" != 'GosDashboard2026!' ] \
		|| [ "$$WAZUH_API_PASSWORD" != 'GosApi2026!Secure' ]; then \
		echo "Wazuh passwords must match the tracked bcrypt hashes and dashboard API config."; \
		echo "Use the Wazuh values from .env.example or update all matching configs together."; \
		exit 1; \
	fi; \
	os=$$(uname -s); \
	if [ "$$os" = "Linux" ]; then \
		value=$$(sysctl -n vm.max_map_count 2>/dev/null || echo 0); \
		case "$$value" in ""|*[!0-9]*) value=0 ;; esac; \
		if [ "$$value" -lt 262144 ]; then \
			echo "Setting vm.max_map_count=262144 for Wazuh Indexer..."; \
			sudo sysctl -w vm.max_map_count=262144; \
			value=$$(sysctl -n vm.max_map_count 2>/dev/null || echo 0); \
			case "$$value" in ""|*[!0-9]*) value=0 ;; esac; \
			if [ "$$value" -lt 262144 ]; then \
				echo "vm.max_map_count is still $$value. Wazuh Indexer requires at least 262144."; \
				exit 1; \
			fi; \
		fi; \
		echo "Wazuh vm.max_map_count=$$value."; \
	else \
		echo "Skipping vm.max_map_count setup on $$os."; \
	fi

# Генерирует TLS-сертификаты Wazuh в Docker volume.
# Сертификаты и private keys не коммитятся в публичный репозиторий.
wazuh-certs: env
	@$(COMPOSE_BASE) up --no-deps gos_siem_certs

# Печатает итоговую compose-конфигурацию Ubuntu-профиля после подстановки .env и override.
config: env
	@$(COMPOSE_DEFAULT) config

# Собирает кастомные образы лабораторных машин и сервисов для Ubuntu-профиля.
build: env
	@$(COMPOSE_DEFAULT) build

# Запускает стенд на Ubuntu VM: перед стартом проверяет занятость портов.
up: check-network check-ports check-wazuh-prereqs wazuh-certs
	@$(COMPOSE_DEFAULT) up -d --build
	@$(MAKE) rdp-info

# Алиас для старых инструкций: основной up теперь уже запускает Ubuntu VM-профиль.
up-vm: up

# Запускает стенд на MacBook: порты доступны только на 127.0.0.1.
up-local: check-network check-ports check-wazuh-prereqs wazuh-certs
	@$(COMPOSE_LOCAL) up -d --build
	@$(MAKE) rdp-info

# Наполняет EspoCRM тестовыми контактами в Ubuntu VM-профиле.
fill-db: env
	@$(COMPOSE_DEFAULT) build gos_db
	@docker rm -f gos_db_seed >/dev/null 2>&1 || true
	@$(COMPOSE_DEFAULT) run --rm --no-deps gos_db_seed

# Наполняет EspoCRM тестовыми контактами в локальном MacBook-профиле.
fill-db-local: env
	@$(COMPOSE_LOCAL) build gos_db
	@docker rm -f gos_db_seed >/dev/null 2>&1 || true
	@$(COMPOSE_LOCAL) run --rm --no-deps gos_db_seed

# Останавливает контейнеры и удаляет только CRM/DB volumes.
# Wazuh, почта и сертификаты сохраняются, чтобы не пересоздавать тяжелые сервисы без необходимости.
down: env
	@$(COMPOSE_DEFAULT) down
	@set -a; . ./$(ENV_FILE); set +a; \
	project=$${COMPOSE_PROJECT_NAME:-gosservice_lab}; \
	for volume in espocrm_data espocrm_custom espocrm_client_custom espocrm_db; do \
		docker volume rm "$${project}_$${volume}" >/dev/null 2>&1 || true; \
	done; \
	echo "Removed CRM/DB volumes for project $$project."

# Показывает состояние контейнеров.
ps: env
	@$(COMPOSE_DEFAULT) ps

# Показывает последние логи и продолжает следить за ними.
logs: env
	@$(COMPOSE_DEFAULT) logs -f --tail=100

# Перезапускает контейнеры без удаления volumes.
restart: env
	@$(COMPOSE_DEFAULT) restart

# Открывает shell внутри adm-контейнера.
shell-adm: env
	@$(COMPOSE_DEFAULT) exec gos_arm_adm bash

# Открывает shell внутри пользовательской машины.
shell-user: env
	@$(COMPOSE_DEFAULT) exec gos_arm_user bash

# Открывает shell внутри внешней рабочей станции.
shell-evil: env
	@$(COMPOSE_DEFAULT) exec gos_arm_evil bash

# Открывает shell внутри роутера.
shell-router: env
	@$(COMPOSE_DEFAULT) exec gos_router bash

# Открывает shell внутри почтового сервера.
shell-mail: env
	@$(COMPOSE_DEFAULT) exec gos_mail bash

# Открывает shell внутри Wazuh Manager.
shell-siem-manager: env
	@$(COMPOSE_DEFAULT) exec gos_siem_manager bash

# Открывает shell внутри Wazuh Indexer.
shell-siem-indexer: env
	@$(COMPOSE_DEFAULT) exec gos_siem_indexer bash

# Открывает shell внутри Wazuh Dashboard.
shell-siem-dashboard: env
	@$(COMPOSE_DEFAULT) exec gos_siem_dashboard bash

# Подключается к adm по SSH через host-порт из .env.
ssh-adm: env
	@set -a; . ./$(ENV_FILE); set +a; \
	ssh -p "$$ADM_SSH_HOST_PORT" "$$LOCALADMIN_USER@127.0.0.1"

# Подключается к user-машине по SSH через host-порт из .env.
ssh-user: env
	@set -a; . ./$(ENV_FILE); set +a; \
	ssh -p "$$USER_SSH_HOST_PORT" "$$USER_USERNAME@127.0.0.1"

# Подключается к evil-машине по опубликованному SSH-порту.
ssh-evil: env
	@set -a; . ./$(ENV_FILE); set +a; \
	ssh -p "$$EVIL_SSH_HOST_PORT" "$$EVIL_USERNAME@127.0.0.1"

# SSH роутера намеренно не публикуется на host: подключаемся через внутреннюю adm-машину.
ssh-router: env
	@set -a; . ./$(ENV_FILE); set +a; \
	$(COMPOSE_DEFAULT) exec gos_arm_adm \
		ssh -o StrictHostKeyChecking=accept-new "$$LOCALADMIN_USER@router.$$GOS_DOMAIN"

# Показывает новые IDS-события Suricata в реальном времени.
suricata-alerts: env
	@$(COMPOSE_DEFAULT) exec gos_router tail -f /var/log/suricata/fast.log

# Печатает актуальные параметры подключения из .env.
rdp-info: env
	@set -a; . ./$(ENV_FILE); set +a; \
	echo "Ubuntu VM access: use <VM_IP> instead of 127.0.0.1 when connecting from another machine."; \
	echo "adm RDP: <VM_IP>:$$ADM_RDP_HOST_PORT"; \
	echo "adm SSH: ssh -p $$ADM_SSH_HOST_PORT $$LOCALADMIN_USER@<VM_IP>"; \
	echo "user RDP: <VM_IP>:$$USER_RDP_HOST_PORT"; \
	echo "user SSH: ssh -p $$USER_SSH_HOST_PORT $$USER_USERNAME@<VM_IP>"; \
	echo "evil RDP: <VM_IP>:$$EVIL_RDP_HOST_PORT"; \
	echo "evil SSH: ssh -p $$EVIL_SSH_HOST_PORT $$EVIL_USERNAME@<VM_IP>"; \
	echo "router SSH: make ssh-router (reachable only through gos_arm_adm/internal_net)"; \
	echo "EspoCRM: http://<VM_IP>:$$ESPOCRM_HTTP_HOST_PORT with Host header crm.$$GOS_DOMAIN"; \
	echo "Wazuh Dashboard: https://<VM_IP>:$$WAZUH_DASHBOARD_HOST_PORT"; \
	echo "MacBook local access after make up-local: replace <VM_IP> with 127.0.0.1."

# Полностью удаляет контейнеры и volumes.
# Использовать только когда нужно сбросить EspoCRM/MariaDB до чистого состояния.
clean-volumes: env
	@$(COMPOSE_DEFAULT) down -v

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
	@$(COMPOSE_DEFAULT) down --volumes --remove-orphans --rmi all || true
	@echo "Deleting fixed-name lab containers left by old deployments..."
	@docker rm -f $(PROJECT_CONTAINERS) >/dev/null 2>&1 || true
	@echo "Deleting lab networks left by current or legacy compose files..."
	@docker network rm $(PROJECT_NETWORKS) >/dev/null 2>&1 || true
	@echo "Deleting standard lab volumes left by current compose project name..."
	@docker volume rm $(PROJECT_VOLUMES) >/dev/null 2>&1 || true
	@echo "Deleting locally built lab images left by compose..."
	@docker image rm $(PROJECT_IMAGES) >/dev/null 2>&1 || true
	@echo "Lab Docker cleanup completed."
