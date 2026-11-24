#!/bin/sh
# Renderiza el vhost con la variable de entorno DOMAIN (default: example.com)
# y arranca Apache en primer plano.
set -e

DOMAIN="${DOMAIN:-example.com}"
envsubst < /etc/apache2/vhost.conf.in > /etc/apache2/sites-enabled/000-site.conf

exec apachectl -D FOREGROUND
