FROM registry.artifakt.io/magento:2.4

ARG ARTIFAKT_COMPOSER_VERSION=2.1.12
ARG CODE_ROOT=.

RUN curl -sS https://getcomposer.org/installer | \
    php -- --version=${ARTIFAKT_COMPOSER_VERSION} --install-dir=/usr/local/bin --filename=composer

WORKDIR /var/www/html

USER www-data
COPY --chown=www-data:www-data $CODE_ROOT /var/www/html/
RUN [ -f composer.lock ] && composer install --no-cache --no-interaction --no-ansi --no-dev || true
RUN php bin/magento module:enable --all

RUN php bin/magento setup:di:compile
RUN composer dump-autoload --no-dev --optimize --apcu
USER root

COPY .artifakt/docker/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

# copy the artifakt folder on root
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN  if [ -d .artifakt ]; then cp -rp /var/www/html/.artifakt/ /.artifakt/; fi

# run custom scripts build.sh
# hadolint ignore=SC1091
RUN --mount=source=artifakt-custom-build-args,target=/tmp/build-args \
  if [ -f /tmp/build-args ]; then source /tmp/build-args; fi && \
  if [ -f /.artifakt/build.sh ]; then /.artifakt/build.sh; fi