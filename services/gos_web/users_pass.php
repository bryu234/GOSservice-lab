<?php

$login    = $_GET['login'] ?? '';
$password = $_GET['password'] ?? '';

if ($login !== 'admin' || $password !== 'xxXX1234!') {
    http_response_code(403);
    exit('403 Forbidden');
}
# отредактировать креды и контейнер для подключения к БД ниже
$mysqli = new mysqli(
    getenv('ESPOCRM_DATABASE_HOST'),
    getenv('ESPOCRM_DATABASE_USER'),
    getenv('ESPOCRM_DATABASE_PASSWORD'),
    getenv('ESPOCRM_DATABASE_NAME')
);

if ($mysqli->connect_errno) {
    die("Ошибка подключения");
}

$result = $mysqli->query("
SELECT
    first_name,
    last_name,
    description
FROM contact
WHERE deleted = 0
ORDER BY last_name, first_name
");

echo "<h2>Контакты EspoCRM</h2>";

echo "<table border='1' cellpadding='6'>";
echo "<tr>
        <th>Имя</th>
        <th>Фамилия</th>
        <th>Описание</th>
      </tr>";

while($row = $result->fetch_assoc()){

    echo "<tr>";
    echo "<td>".$row['first_name']."</td>";
    echo "<td>".$row['last_name']."</td>";
    echo "<td>".$row['description']."</td>";
    echo "</tr>";

}

echo "</table>";

?>