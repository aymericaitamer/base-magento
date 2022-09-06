#!/bin/bash
# Author: Aymeric Mathéossian - Head Of Customer Success
# Created: 15/08/2022
# Version: 1.0

set -e
### CONFIGURATION FILES - !! DO NOT EDIT
ROOT_PROJECT="/var/www/html"
NGINX_CONFIG_DEST_FOLDER="/conf/nginxfpm"
NGINX_CONFIG_SRC_FOLDER="$ROOT_PROJECT/.artifakt/nginx"
NGINX_CONFIG_FILES=('custom_global' 'custom_media' 'custom_server_location' 'custom_server' 'custom_upstream')

VARNISH_CONFIG_DEST_FOLDER="/conf/varnish"
VARNISH_CONFIG_SRC_FOLDER="$ROOT_PROJECT/.artifakt/varnish"
VARNISH_CONFIG_FILES=('custom_backends' 'custom_end_rules' 'custom_process_graphql_headers' 'custom_start_rules' 'custom_vcl_backend_response' 'custom_vcl_deliver' 'custom_vcl_hash' 'custom_vcl_hit' 'custom_vcl_recv' 'default')

PERSISTENT_FOLDER_LIST=('pub/media' 'pub/static' 'var')

MAGENTO_CONFIG_SRC_FOLDER=".artifakt/magento"
MAGENTO_CONFIG_DEST_FOLDER="$ROOT_PROJECT/app/etc"
##########################################

echo "######################################################"
echo "##### NGINX CONFIGURATION"
echo "Src folder: $NGINX_CONFIG_SRC_FOLDER"
echo "Dest folder: $NGINX_CONFIG_DEST_FOLDER"
echo ""

echo ">> CLEANING CONF FOLDER"
rm -rf $NGINX_CONFIG_DEST_FOLDER/*
echo ""

echo ">> GLOBAL CONFIGURATIONS FILE"
for analyze_nginx_config_file in ${NGINX_CONFIG_FILES[@]}; do
  echo "CHECKING: $analyze_nginx_config_file"
  if [ -f "$NGINX_CONFIG_SRC_FOLDER/$analyze_nginx_config_file.conf" ]; then
    echo "FILE DETECTED - COPY TO CONF FOLDER"
    cp $NGINX_CONFIG_SRC_FOLDER/$analyze_nginx_config_file.conf $NGINX_CONFIG_DEST_FOLDER/
  else
    echo "FILE NOT DETECTED - CREATING EMPTY FILE IN CONF FOLDER"
    touch $NGINX_CONFIG_DEST_FOLDER/$analyze_nginx_config_file.conf
  fi
done
echo ""

echo ">> MULTI-STORE MAP FILE CONFIGURATION"
echo "-------------------"
echo "INFO: to use a mapping file, remember to set the CURRENT_ENV variable in the console and create a file in your .artifakt/nginx folder"
echo "INFO: The Map fil is used by Magento to find the match between the url and the website or store code."
echo "-------------------"
if [[ ! -z $CURRENT_ENV ]]; then
  echo "CHECKING CURRENT_ENV VARIABLE: $CURRENT_ENV"
  echo "CHECKING FILE: $NGINX_CONFIG_SRC_FOLDER/custom_http.conf.$CURRENT_ENV"
  if [ -f $NGINX_CONFIG_SRC_FOLDER/custom_http.conf.$CURRENT_ENV ]; then
    echo "FILE DETECTED - COPY TO CONF FOLDER"
    cp $NGINX_CONFIG_SRC_FOLDER/custom_http.conf.$CURRENT_ENV $NGINX_CONFIG_DEST_FOLDER/custom_http.conf
  else
    echo "FILE NOT DETECTED - CREATING EMPTY FILE IN CONF FOLDER"
    touch $NGINX_CONFIG_DEST_FOLDER/custom_http.conf
  fi
  echo "Creation of the file custom_server_location.conf"
  echo "# Following code is included in the “location” block of main server block" > $NGINX_CONFIG_DEST_FOLDER/custom_server_location.conf
  echo "fastcgi_param HTTPS \"on\";"  >> $NGINX_CONFIG_DEST_FOLDER/custom_server_location.conf
  echo "fastcgi_param MAGE_RUN_TYPE \"website\";" >> $NGINX_CONFIG_DEST_FOLDER/custom_server_location.conf
  echo "fastcgi_param MAGE_RUN_CODE \$MAGE_RUN_CODE;" >> $NGINX_CONFIG_DEST_FOLDER/custom_server_location.conf
else
  echo "CURRENT ENV VARIABLE: NOT DECLARATED - CREATING EMPTY FILE IN CONF FOLDER"
  touch $NGINX_CONFIG_DEST_FOLDER/custom_http.conf
fi
echo ""

echo ">> Content of configuration folders $NGINX_CONFIG_DEST_FOLDER"
ls -la $NGINX_CONFIG_DEST_FOLDER

echo ""
echo ""
echo "######################################################"
echo "##### VARNISH CONFIGURATION"

echo "Src folder: $VARNISH_CONFIG_SRC_FOLDER"
echo "Dest folder: $VARNISH_CONFIG_DEST_FOLDER"
echo ""

echo ">> CLEANING CONF FOLDER"
rm -rf $VARNISH_CONFIG_DEST_FOLDER/*
echo ""

echo ">> GLOBAL CONFIGURATIONS FILE"
for analyze_varnish_config_file in ${VARNISH_CONFIG_FILES[@]}; do
  echo "CHECKING: $analyze_varnish_config_file.vcl"
  if [ -f "$VARNISH_CONFIG_SRC_FOLDER/$analyze_varnish_config_file.vcl" ]; then
    echo "FILE DETECTED - COPY TO CONF FOLDER"
    cp $VARNISH_CONFIG_SRC_FOLDER/$analyze_varnish_config_file.vcl $VARNISH_CONFIG_DEST_FOLDER/
  else
    echo "FILE NOT DETECTED - CREATING EMPTY FILE IN CONF FOLDER"
    touch $VARNISH_CONFIG_DEST_FOLDER/$analyze_varnish_config_file.vcl
  fi
done

echo ">> Content of configuration folders $VARNISH_CONFIG_DEST_FOLDER"
ls -la $VARNISH_CONFIG_DEST_FOLDER

echo ""
echo "######################################################"
echo "##### Files mapping CONFIGURATION"
echo ""

# Improvment
#echo "DEBUG: waiting for database to be available..."
#wait-for $ARTIFAKT_MYSQL_HOST:3306 --timeout=90 -- echo "Mysql is up, proceeding with starting sequence"


for persistent_folder in ${PERSISTENT_FOLDER_LIST[@]}; do

  echo Init persistent folder /data/$persistent_folder
  mkdir -p /data/$persistent_folder

  echo Copy modified/new files from container /var/www/html/$persistent_folder to volume /data/$persistent_folder
  rsync -rtv /var/www/html/$persistent_folder/ /data/$persistent_folder || true

  echo Link /data/$persistent_folder directory to /var/www/html/$persistent_folder
  rm -rf /var/www/html/$persistent_folder && \
    mkdir -p /var/www/html && \
    ln -sfn /data/$persistent_folder /var/www/html/$persistent_folder && \
    chown -h -R -L www-data:www-data /var/www/html/$persistent_folder /data/$persistent_folder
done

echo "######################################################"
echo "##### MAGENTO OPERATIONS"
echo ""

echo ">> CHECK IF THE DATABASE IS INSTALLED"
tableCount=$(mysql -h $ARTIFAKT_MYSQL_HOST -u $ARTIFAKT_MYSQL_USER -p$ARTIFAKT_MYSQL_PASSWORD $ARTIFAKT_MYSQL_DATABASE_NAME -B -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = '$ARTIFAKT_MYSQL_DATABASE_NAME';" | grep -v "count");
echo ">>> Number of tables: $tableCount"

if [ $tableCount -ne 0 ]
then
  ENV_FILE_CHECK=0
  echo ">> CHECKING THE ENV FILE: $MAGENTO_CONFIG_SRC_FOLDER: env.php.sample"
  if [ -f "$MAGENTO_CONFIG_SRC_FOLDER/env.php.sample" ]
  then
    ENV_FILE_CHECK=1
    mv $MAGENTO_CONFIG_SRC_FOLDER/env.php.sample $MAGENTO_CONFIG_DEST_FOLDER/env.php
    echo "ENV FILE FOUND AND COPIED TO $MAGENTO_CONFIG_DEST_FOLDER/env.php"
  else
    echo "ENV FILE NOT FOUND"
    echo "ERROR ! CANNOT FIND THE FILE $MAGENTO_CONFIG_SRC_FOLDER/env.php.sample"
  fi
  if [ -f "$MAGENTO_CONFIG_DEST_FOLDER/env.php" ]; then ENV_FILE_CHECK=1; fi

  if [ $ENV_FILE_CHECK -eq 1 ]; then
    # Update database and/or configuration if changes
    if [ $ARTIFAKT_IS_MAIN_INSTANCE == 1 ]; then

      # read db and config statuses 
      # while temporary disabling errors
      echo ">> STARTING DATABASE OPERATIONS"
      set +e
      bin/magento setup:db:status
      dbStatus=$?
      bin/magento app:config:status
      configStatus=$?
      set -e

      echo "> Result of setup:db:status : $dbStatus"
      echo "> Result of app:config:status : $configStatus"
      
      if [[ $dbStatus == 2 || $configStatus == 2 ]];then
        echo "Put 'current/live' release under maintenance"
        set -e
        su www-data -s /bin/bash -c "php bin/magento maintenance:enable"
        set +e
        echo "=> Maintenance enabled."
      fi

      if [ "$(bin/magento app:config:status)" != "Config files are up to date." ]; then      
          echo "Configuration needs app:config:import";
          su www-data -s /bin/bash -c "php bin/magento app:config:import --no-interaction"
          echo "=> Configuration is now up to date.";
      else
          echo "=> Configuration is already up to date.";
      fi

      
      if [ $dbStatus == 2 ]; then
        set -e
        echo "The database needs to be updated"
        echo "=> Running setup:db-schema:upgrade"
        su www-data -s /bin/bash -c "php bin/magento setup:db-schema:upgrade --no-interaction"
        echo "=> Running setup:db-data:upgrade"
        su www-data -s /bin/bash -c "php bin/magento setup:db-data:upgrade --no-interaction"
        set +e
      fi

      echo "Remove 'current/live' release under maintenance"
      if [[ $dbStatus == 2 || $configStatus == 2 ]];    then
        set -e
        su www-data -s /bin/bash -c "php bin/magento maintenance:disable"
        echo "=> Maintenance disabled"   
        set +e
      fi

      echo ">> END OF DATABASE OPERATIONS"
      if [ -z $MAGE_MODE ]; then 
        MAGE_MODE="production"
      fi

      if [ "$MAGE_MODE" = "production" ]; then
        echo "!> PRODUCTION MODE DETECTED"
        echo ">> STATIC CONTENT DEPLOY"
        echo "INFO: for each parameter, you have below each Environment Variable you can use to customize the deployment."
        echo "Jobs (ARTIFAKT_MAGE_STATIC_JOBS): ${ARTIFAKT_MAGE_STATIC_JOBS:-5}"
        echo "Content version: $ARTIFAKT_BUILD_ID"
        echo "Theme (ARTIFAKT_MAGE_STATIC_THEME): ${ARTIFAKT_MAGE_STATIC_THEME:-all}"
        echo "Theme excluded (ARTIFAKT_MAGE_THEME_EXCLUDE): ${ARTIFAKT_MAGE_THEME_EXCLUDE:-none}"
        echo "Language excluded (ARTIFAKT_MAGE_LANG_EXCLUDE): ${ARTIFAKT_MAGE_LANG_EXCLUDE:-none}"
        echo "Languages (ARTIFAKT_MAGE_LANG): ${ARTIFAKT_MAGE_LANG:-all}"
        set -e
        su www-data -s /bin/bash -c "php bin/magento setup:static-content:deploy -f --no-interaction --jobs ${ARTIFAKT_MAGE_STATIC_JOBS:-5}  --content-version=${ARTIFAKT_BUILD_ID} --theme="${ARTIFAKT_MAGE_STATIC_THEME:-all}" --exclude-theme="${ARTIFAKT_MAGE_THEME_EXCLUDE:-none}" --exclude-language="${ARTIFAKT_MAGE_LANG_EXCLUDE:-none}" ${ARTIFAKT_MAGE_LANG:-all}"
        set +e
      else
        echo "!> DEVELOPER MODE DETECTED - SWITCH"
        su www-data -s /bin/bash -c "bin/magento deploy:mode:set developer"
      fi
    else
      echo ">> DB UPDATE: WAITING FOR THE DB TO BE READY (ACTIONS DONE ON MAIN INSTANCE)"
      until bin/magento setup:db:status && bin/magento app:config:status
      do
        echo "The main instance is not ready..."
        sleep 10
      done
    fi # end of "Update database and/or configuration if changes"

    if [ ! -z $ARTIFAKT_REPLICA_LIST ]; then 
      if [ -z $SET_VARNISH ]; then
        echo "VARNISH / env.php - ENABLE VARNISH AS CACHE BACKEND"
        echo "REPLICA LIST: $ARTIFAKT_REPLICA_LIST"
        echo "INFO: You can deactivate this by setting the SET_VARNISH to 0 (or anything you want)"
        echo "Activating Varnish in env.php file"
        su www-data -s /bin/bash -c "php bin/magento config:set --scope=default --scope-code=0 system/full_page_cache/caching_application 2"
        su www-data -s /bin/bash -c "php bin/magento setup:config:set --http-cache-hosts=${ARTIFAKT_REPLICA_LIST} --no-interaction;"
      fi
    fi
    #6 fix owner/permissions on var/{cache,di,generation,page_cache,view_preprocessed}
    echo ">> PERMISSIONS -  Fix owner/permissions on var/{cache,di,generation,page_cache,view_preprocessed}"
    find var generated vendor pub/static pub/media app/etc -type f -exec chown www-data:www-data {} +
    find var generated vendor pub/static pub/media app/etc -type d -exec chown www-data:www-data {} +

    find var generated vendor pub/static pub/media app/etc -type f -exec chmod g+w {} +
    find var generated vendor pub/static pub/media app/etc -type d -exec chmod g+ws {} +

    echo ">> PERMISSIONS - Fix owner on dynamic data"
    chown -R www-data:www-data /var/www/html/pub/static
    chown -R www-data:www-data /var/www/html/pub/media
    chown -R www-data:www-data /var/www/html/var/log
    chown -R www-data:www-data /var/www/html/var/page_cache

    # Copy all files in shared folder to allow nginx to access it
    if [ $ARTIFAKT_IS_MAIN_INSTANCE -eq 1 ]; then
      echo ">> COPY FILES FOR NGINX: statics, js and files in pub"
      echo "Create /data/pub if it doesn't exist"
      mkdir -p /data/pub
      echo "Switch owner to www-data"
      chown www-data:www-data /data/pub
      echo "Copy all changed files from /var/www/html/pub/static/* to /data/pub/static"
      rsync -rtv /var/www/html/pub/static/ /data/pub/static/
      #su www-data -s /bin/bash -c "cp -pur /var/www/html/pub/js/* /data/pub/js || true"
      echo "Copy all files in pub (no subdirectories)"
      rsync -rtv ./pub/* /data/pub/
    fi

    echo ">> CHECKING IF NEWRELIC HAS TO BE INSTALLED"
    echo "INFO: to deploy newrelic, set these variables: NEWRELIC_KEY, NEWRELIC_APPNAME, NEWRELIC_VERSION"
    echo ""
    if [ ! -z $NEWRELIC_KEY ] && [ ! -z $NEWRELIC_APPNAME ] && [ ! -z $NEWRELIC_VERSION ]; then
      echo "NEWRELIC_KEY, NEWRELIC_APPNAME, NEWRELIC_VERSION found"
      echo "NEWRELIC_KEY: $NEWRELIC_KEY"
      echo "NEWRELIC_APPNAME: $NEWRELIC_APPNAME"
      echo "NEWRELIC_VERSION: $NEWRELIC_VERSION"
      echo "Newrelic installation started"
      curl -L https://download.newrelic.com/php_agent/archive/${NEWRELIC_VERSION}/newrelic-php5-${NEWRELIC_VERSION}-linux.tar.gz | tar -C /tmp -zx
      export NR_INSTALL_SILENT=true
      /tmp/newrelic-php5-${NEWRELIC_VERSION}-linux/newrelic-install install && \
      sed -i \
        -e 's/"REPLACE_WITH_REAL_KEY"/'$NEWRELIC_KEY'/' \
        -e 's/newrelic.appname =.*/newrelic.appname = '$NEWRELIC_APPNAME'/' \
        /usr/local/etc/php/conf.d/newrelic.ini
      chown www-data:www-data /var/log/newrelic
      echo "Newrelic installation finished"

      ## LOGS SCRIPT START
      
      ## LOGS SCRIPT END
    else
      echo "Variables not found, NewRelic won't be deployed."
    fi
  else
    echo "ERROR - NO ENV FILE, MAGENTO OPERATIONS SKIPPED"
  fi # end of actions if env file exists
else
  echo "ERROR - MAGENTO IS NOT INSTALLED YET (NO TABLES FOUND)"
fi # end of actions if Magento is installed


