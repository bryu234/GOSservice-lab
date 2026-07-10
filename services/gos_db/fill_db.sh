#!/usr/bin/env bash
# Наполнение таблицы contact тестовыми данными для EspoCRM.
# Скрипт запускается после первичной установки EspoCRM, поэтому таблицу не создает.
set -euo pipefail

db_host="${ESPOCRM_DB_HOST:-gos_db}"
db_user="${ESPOCRM_DB_USER:-espocrm}"
db_pass="${ESPOCRM_DB_PASSWORD:-CHANGE_ME_ESPOCRM_DB_PASSWORD}"
db_name="${ESPOCRM_DB_NAME:-espocrm}"

first_names=("Иван" "Петр" "Алексей" "Мария" "Анна" "Дмитрий" "Елена" "Сергей" "Ольга" "Игорь")
last_names=("Смирнов" "Иванов" "Кузнецов" "Попов" "Васильев" "Петров" "Соколов" "Михайлов" "Новиков" "Федоров")
cities=("Москва" "Санкт-Петербург" "Новосибирск" "Екатеринбург" "Казань")
streets=("Ленина" "Пушкина" "Садовая" "Лесная" "Новая")
countries=("Россия" "Беларусь" "Казахстан")
domains=("gmail.com" "mail.ru" "yandex.ru" "company.com")

execute_sql() {
  local sql="$1"
  mariadb \
    --host="$db_host" \
    --user="$db_user" \
    --password="$db_pass" \
    --default-character-set=utf8mb4 \
    "$db_name" \
    -e "$sql"
}

wait_for_contact_table() {
  echo "Ожидание таблицы contact в базе $db_name на $db_host..."

  for attempt in $(seq 1 60); do
    table_count="$(execute_sql "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = '$db_name' AND table_name = 'contact';" 2>/dev/null | tail -1 || true)"
    if [ "$table_count" = "1" ]; then
      echo "Таблица contact найдена."
      return 0
    fi

    echo "Таблица contact еще не готова, попытка ${attempt}/60."
    sleep 2
  done

  echo "Таблица contact не появилась вовремя."
  return 1
}

fill_contacts() {
  echo "Очистка и наполнение contact тестовыми данными..."

  sql_query="SET FOREIGN_KEY_CHECKS=0; TRUNCATE TABLE contact; SET FOREIGN_KEY_CHECKS=1; START TRANSACTION;"
  sql_query+="INSERT INTO contact (id, first_name, last_name, deleted, do_not_call, description, address_street, address_city, address_country, address_postal_code, created_at, modified_at) VALUES "
  sql_query+="('lab-contact-0001', 'Test', 'Test', 0, 0, 'Тестовая запись. Тел: +79001112233. Email: admin@espocrm.local', 'ул. Тестовая, 1', 'Москва', 'РФ', '101000', NOW(), NOW())"

  for i in $(seq 2 51); do
    contact_id="$(printf 'lab-contact-%04d' "$i")"
    f_name="${first_names[$RANDOM % ${#first_names[@]}]}"
    l_name="${last_names[$RANDOM % ${#last_names[@]}]}"

    if [[ "$f_name" == "Мария" || "$f_name" == "Анна" || "$f_name" == "Елена" || "$f_name" == "Ольга" ]]; then
      l_name="${l_name}а"
    fi

    city="${cities[$RANDOM % ${#cities[@]}]}"
    street="ул. ${streets[$RANDOM % ${#streets[@]}]}, д. $((RANDOM % 100 + 1))"
    country="${countries[$RANDOM % ${#countries[@]}]}"
    postal_code="$((RANDOM % 899999 + 100000))"
    phone="+7911$((RANDOM % 8999999 + 1000000))"
    email="user_${i}@${domains[$RANDOM % ${#domains[@]}]}"
    description="Тел: $phone. Email: $email."
    rand_hours="$((RANDOM % 720))"

    sql_query+=", ('$contact_id', '$f_name', '$l_name', 0, 0, '$description', '$street', '$city', '$country', '$postal_code', TIMESTAMPADD(HOUR, -$rand_hours, NOW()), NOW())"
  done

  sql_query+="; COMMIT;"
  execute_sql "$sql_query"
}

main() {
  echo "=================================================="
  echo "Загрузка тестовых контактов для EspoCRM"
  echo "База данных: $db_name на сервере $db_host"
  echo "=================================================="

  wait_for_contact_table
  fill_contacts

  echo "--------------------------------------------------"
  execute_sql "SELECT COUNT(*) AS contact_count FROM contact;"
  execute_sql "SELECT id, first_name, last_name, address_city, description FROM contact WHERE id = 'lab-contact-0010' LIMIT 1;"
  echo "Данные клиентов успешно загружены."
  echo "=================================================="
}

main "$@"
