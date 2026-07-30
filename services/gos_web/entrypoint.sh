#!/bin/bash
set -e

mkdir -p /run/php

PHP_FPM=$(find /usr/sbin -name "php-fpm*" | head -n1)
$PHP_FPM -D

exec nginx -g "daemon off;"