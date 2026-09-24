#!/usr/bin/env bash
set -euo pipefail

ESPO_DIR=/var/www/espocrm
admin_user="${LOCALADMIN_USER:-localadmin}"
admin_password="${LOCALADMIN_PASSWORD:-CHANGE_ME_LOCALADMIN_PASSWORD}"
external_subnet="${GOS_EXTERNAL_SUBNET:-172.28.8.0/24}"
router_internal_ip="${GOS_ROUTER_INTERNAL_IP:-10.10.20.254}"

# Кодируем значения для передачи в install/cli.php через query-string.
urlencode() {
    php -r 'echo rawurlencode($argv[1]);' "$1"
}

# Выполняет действие CLI-инсталлятора EspoCRM.
run_install_action() {
    local action="$1"
    local data="${2:-}"

    if [ -n "$data" ]; then
        php "$ESPO_DIR/install/cli.php" -a "$action" -d "$data"
    else
        php "$ESPO_DIR/install/cli.php" -a "$action"
    fi
}

# Надежно проверяет признак установки в data/config.php.
# В старых EspoCRM config может не быть isInstalled и database-ключа в новой форме,
# но сам факт непустого data/config.php означает, что web-приложение уже настроено.
is_espocrm_installed() {
    if [ ! -f "$ESPO_DIR/data/config.php" ]; then
        return 1
    fi

    php -r '$config = include $argv[1]; exit((is_array($config) && count($config) > 0) ? 0 : 1);' "$ESPO_DIR/data/config.php"
}

# Ждем MariaDB, потому что install/cli.php сразу проверяет подключение и строит схему.
wait_for_database() {
    echo "Waiting for MariaDB at ${ESPOCRM_DATABASE_HOST}..."

    for attempt in $(seq 1 60); do
        if mariadb-admin ping \
            -h"${ESPOCRM_DATABASE_HOST}" \
            -u"${ESPOCRM_DATABASE_USER}" \
            -p"${ESPOCRM_DATABASE_PASSWORD}" \
            --silent >/dev/null 2>&1; then
            echo "MariaDB is ready."
            return 0
        fi

        echo "MariaDB is not ready yet, attempt ${attempt}/60."
        sleep 2
    done

    echo "MariaDB did not become ready in time."
    return 1
}

# Подготавливаем writable-каталоги EspoCRM, в том числе те, что могут быть docker volumes.
prepare_permissions() {
    mkdir -p \
        "$ESPO_DIR/data" \
        "$ESPO_DIR/custom" \
        "$ESPO_DIR/client/custom" \
        "$ESPO_DIR/install"

    chown -R www-data:www-data \
        "$ESPO_DIR/data" \
        "$ESPO_DIR/custom" \
        "$ESPO_DIR/client/custom" \
        "$ESPO_DIR/install"
}

# Создает локального администратора для SSH-доступа с adm-машины.
setup_admin_ssh() {
    if ! id "$admin_user" >/dev/null 2>&1; then
        useradd -m -s /bin/bash "$admin_user"
    fi

    echo "$admin_user:$admin_password" | chpasswd
    usermod -aG sudo "$admin_user"

    cat >/etc/sudoers.d/gos-localadmin <<EOF
$admin_user ALL=(ALL:ALL) ALL
EOF
    chmod 0440 /etc/sudoers.d/gos-localadmin

    mkdir -p /run/sshd
    chmod 755 /run/sshd
    ssh-keygen -A >/dev/null 2>&1 || true
    sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config || true
    sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config || true
}

# Первичная установка EspoCRM выполняется один раз.
# Признак установки хранится в data/config.php внутри persistent volume.
install_espocrm_if_needed() {
    if is_espocrm_installed; then
        echo "EspoCRM is already installed."
        return 0
    fi

    echo "Installing EspoCRM ${ESPOCRM_VERSION}..."

    local db_name db_host db_user db_pass site_url admin_user admin_pass
    db_name="$(urlencode "${ESPOCRM_DATABASE_NAME}")"
    db_host="$(urlencode "${ESPOCRM_DATABASE_HOST}")"
    db_user="$(urlencode "${ESPOCRM_DATABASE_USER}")"
    db_pass="$(urlencode "${ESPOCRM_DATABASE_PASSWORD}")"
    site_url="$(urlencode "${ESPOCRM_SITE_URL}")"
    admin_user="$(urlencode "${ESPOCRM_ADMIN_USERNAME}")"
    admin_pass="$(urlencode "${ESPOCRM_ADMIN_PASSWORD}")"

    # Сохраняем параметры БД в install-session.
    run_install_action "step2" "db-platform=Mysql&db-name=${db_name}&host-name=${db_host}&db-user-name=${db_user}&db-user-password=${db_pass}&site-url=${site_url}&user-lang=en_US"

    # Отдельно проверяем подключение к БД теми ключами, которые ожидает AJAX-action installer.
    run_install_action "settingsTest" "dbPlatform=Mysql&dbName=${db_name}&hostName=${db_host}&dbUserName=${db_user}&dbUserPass=${db_pass}"

    # Пишем data/config.php и строим схему EspoCRM.
    run_install_action "saveSettings"
    run_install_action "buildDatabase"

    # Создаем администратора из .env.
    run_install_action "step3" "user-name=${admin_user}&user-pass=${admin_pass}&user-confirm-pass=${admin_pass}"
    run_install_action "createUser"

    # Фиксируем базовые настройки интерфейса и завершаем установку.
    run_install_action "step4" "language=en_US&timeZone=UTC&dateFormat=YYYY-MM-DD&timeFormat=HH:mm&weekStart=1&defaultCurrency=USD&thousandSeparator=,&decimalMark=."
    run_install_action "savePreferences"
    run_install_action "finish"

    chown -R www-data:www-data "$ESPO_DIR/data" "$ESPO_DIR/custom" "$ESPO_DIR/client/custom"

    echo "EspoCRM installation completed."
}

prepare_permissions
setup_admin_ssh

# Ответы внешней машине должны возвращаться тем же путем через gos_router,
# а не через стандартный gateway Docker bridge.
ip route replace "$external_subnet" via "$router_internal_ip"

wait_for_database
install_espocrm_if_needed

# Entry point запускает nginx в daemon-режиме, необходимом для штатной замены
# бинарника через USR2, а затем оставляет SSHD процессом PID 1 контейнера.
bash /usr/local/bin/gos-rsyslog.sh initialize disabled
bash /usr/local/bin/gos-rsyslog.sh start optional

echo "Starting nginx $(nginx -v 2>&1)..."
exec /usr/local/bin/gos-website-entrypoint
