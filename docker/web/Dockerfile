# Apache sobre Debian 13 (trixie) con proxy_fcgi hacia PHP-FPM.
# En trixie el módulo proxy_fcgi viene con apache2 (el paquete transitional
# libapache2-mod-proxy-fcgi de bookworm ya no existe); basta a2enmod proxy_fcgi.
FROM debian:trixie

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        apache2 \
        gettext-base \
    && rm -rf /var/lib/apt/lists/*

# Habilita el módulo proxy_fcgi (dependencia proxy se resuelve sola).
RUN a2enmod proxy_fcgi

# Vhost HTTP-only (mirror del branch "LE deshabilitado" del template Ansible):
# DocumentRoot + PHP vía proxy:tcp://php-fpm:9000. El placeholder ${DOMAIN}
# se renderiza con envsubst al arrancar (compose siempre define DOMAIN).
COPY vhost.conf /etc/apache2/vhost.conf.in
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh \
    && a2dissite 000-default.conf

# Document root (se sobrescribe por el montaje ./site:/var/www/html).
RUN mkdir -p /var/www/html

# Log de Apache accesible desde el host para depurar.
VOLUME /var/log/apache2

EXPOSE 80

CMD ["/entrypoint.sh"]
