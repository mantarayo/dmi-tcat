#!/bin/bash

# Fixed parameters

WEBUSER=www-data
WEBGROUP=www-data

# Make sure only root can run our script

if [ "$(id -u)" != "0" ]; then
   tput setaf 1
   echo "This script must be run as root" 1>&2
   tput sgr0
   exit 1
fi

tput clear

echo ""
echo "Welcome to the DMI TCAT installation script"
echo "==========================================="
echo ""

# Test OS version

ISSUE=`cat /etc/issue`
# Example: Ubuntu 14.04.3 LTS \n \l
REGEX="Ubuntu ([0-9]*)\.([0-9]*)"
[[ $ISSUE =~ $REGEX ]]
MAJOR="${BASH_REMATCH[1]}"
MINOR="${BASH_REMATCH[2]}"
if [ -z "$MAJOR" ]; then
   echo "It does not look like you are running Ubuntu. This is an Ubuntu installation script. Exiting."
   exit;
else
   if [ "$MAJOR" -lt "15" ]; then
      echo "You are running an older version of Ubuntu and will NOT be able to do geometrical searches!"
      echo ""
      read -p "Do you want to consider upgrading your distribution before running the installation script ([y]es/[n]o)?" YESNO
      if [ "$YESNO" == "y" ]; then
          echo "Exiting."
          exit
      fi
   else
      echo "You are running a recent version of Ubuntu and will be able to do geometrical searches."
   fi
fi

echo ""
echo "Before installation, you will to fill in some information about your server configuration."
echo ""

# Get user parameters

read -p "Server name for TCAT: " SERVERNAME
read -p "Shell username for TCAT ownership (usually a SSH user, but don't use root): " SHELLUSER
read -p "Shell group name for TCAT ownership (usually the same as the username): " SHELLGROUP
read -p "Username for administrating MySQL databases (usually root): " DBUSER
DBPASS=""
while [ -z "$DBPASS" ]; do
   read -s -p "MySQL administrative password (repeat this password during the MySQL package install!): " DBPASS1
   echo
   read -s -p "Repeat MySQL administrative password: " DBPASS2
   echo
   if [ "$DBPASS1" != "$DBPASS2" ]; then
      echo "Passwords do not match! Please try again."
   else
      DBPASS=$DBPASS1
   fi
done
tput setaf 1
echo "!!"
echo "Remember to REPEAT this password later during the install, when you are asked: \"New password for the MySQL \"root\" user\" !!"
echo "!!"
tput sgr0
echo "(press enter once to continue ..)"
read
read -p "Please provide a (new) username for the TCAT MySQL database (for example: tcatdbuser, but don't use root): " TCATMYSQLUSER
TCATMYSQLPASS=""
while [ -z "$TCATMYSQLPASS" ]; do
   read -s -p "MySQL password for the user: " MYSQLPASS1
   echo
   read -s -p "Repeat the user password: " MYSQLPASS2
   echo
   if [ "$MYSQLPASS1" != "$MYSQLPASS2" ]; then
      echo "Passwords do not match! Please try again."
   else
      TCATMYSQLPASS=$MYSQLPASS1
   fi
done
read -p "Please provide a TCAT administrative username for the web-frontend (for example admin): " TCATADMINUSER
TCATADMINPASS=""
while [ -z "$TCATADMINPASS" ]; do
   read -s -p "TCAT administrative password: " TCATADMINPASS1
   echo
   read -s -p "Repeat TCAT administrative password: " TCATADMINPASS2
   echo
   if [ "$TCATADMINPASS1" != "$TCATADMINPASS2" ]; then
      echo "Passwords do not match! Please try again."
   else
      TCATADMINPASS=$TCATADMINPASS1
   fi
done
read -p "Please provide the name of an unprivileged TCAT user for the web-frontend (for example: tcat) " TCATUSER
TCATPASS=""
while [ -z "$TCATPASS" ]; do
   read -s -p "TCAT user password: " TCATPASS1
   echo
   read -s -p "Repeat TCAT user password: " TCATPASS2
   echo
   if [ "$TCATPASS1" != "$TCATPASS2" ]; then
      echo "Passwords do not match! Please try again."
   else
      TCATPASS=$TCATPASS1
   fi
done
echo ""
echo "The URL expander periodically expands URLs in Tweets by fully resolving their addresses. This improves the searchability of your datasets,"
echo "but increases your network traffic."
echo ""
URLEXPANDYES=""
while [ "$URLEXPANDYES" != "y" ] && [ "$URLEXPANDYES" != "n" ]; do
   read -p "Would you like to set up automatic expansion of URLs (y/n)? " URLEXPANDYES
   if [ "$URLEXPANDYES" != "y" ] && [ "$URLEXPANDYES" != "n" ]; then
       echo "Unrecognized input! Please try again."
   fi
done

# Install

echo ""
echo "Thank you. Now starting installation ..."
echo ""

# Clear any existing TCAT crontab references
echo "" > /etc/cron.d/tcat
# These lines used to be written to the global /etc/crontab file
sed -i 's/^# Run TCAT controller every minute$//g' /etc/crontab
sed -i 's/^.*cd \/var\/www\/dmi-tcat\/capture\/stream\/; php controller.php.*$//g' /etc/crontab
sed -i 's/^# Run DMI-TCAT URL expander every hour$//g' /etc/crontab
sed -i 's/^.*cd \/var\/www\/dmi-tcat\/helpers; sh urlexpand.sh.*$//g' /etc/crontab

tput bold
echo "Installing basic prerequisites ..."
tput sgr0
echo ""

apt-get update
apt-get -y upgrade
apt-get -y install wget debsums

tput bold
echo "Installing MySQL server and Apache webserver ..."
tput sgr0
echo ""

apt-get -y install mysql-server-5.6 mysql-client-5.6 apache2-mpm-prefork apache2-utils libapache2-mod-php5 php5-mysql php5-curl php5-cli php-patchwork-utf8 git curl
if [ "$MAJOR" -gt "14" ]; then
   apt-get -y install php5-geos
   php5enmod geos
fi
# Installation and autoconfiguration of MySQL will not work with Apparmor profile enabled
ln -s /etc/apparmor.d/usr.sbin.mysqld /etc/apparmor.d/disable/
/etc/init.d/apparmor restart 

echo ""
tput bold
echo "Downloading DMI-TCAT from github ..."
tput sgr0
echo ""

git clone https://github.com/digitalmethodsinitiative/dmi-tcat.git /var/www/dmi-tcat

echo ""
tput bold
echo "Preliminary DMI-TCAT configuration ..."
tput sgr0
echo ""

chown -R $SHELLUSER:$SHELLGROUP /var/www/dmi-tcat/
cd /var/www/dmi-tcat
mkdir analysis/cache logs proc
chown $WEBUSER:$WEBGROUP analysis/cache
chmod 755 analysis/cache
chown $SHELLUSER:$SHELLGROUP logs proc
chmod 755 logs
chmod 755 proc

echo ""
tput bold
echo "Configuring Apache 2 ..."
tput sgr0
echo ""

read -d '' APACHECONF1 <<"EOF"
<VirtualHost *:80>
EOF
read -d '' APACHECONF2 <<"EOF"
        DocumentRoot /var/www/dmi-tcat/

        RewriteEngine On
        RewriteRule ^/$ /analysis/ [R,L]

        <Directory />
                Options FollowSymLinks
                AllowOverride None
        </Directory>

        <Directory /var/www/dmi-tcat/>
            # make sure directory lists are not possible
            Options -Indexes
            # basic authentication
            AuthType Basic
            AuthName "Log in to DMI-TCAT"
            AuthBasicProvider file
            AuthUserFile /etc/apache2/passwords
EOF
read -d '' APACHECONF3 <<"EOF"
            DirectoryIndex index.html index.php
            # some directories and files should not be accessible via the web, make sure to enable mod_rewrite
            RewriteEngine on
            RewriteRule ^(cli|helpers|import|logs|proc|config.php|capture/common|capture/klout|capture/pos|capture/search|capture/stream|/capture/user) - [F,L,NC]
        </Directory>
</VirtualHost>
EOF
echo "$APACHECONF1"  > /etc/apache2/sites-available/tcat.conf
echo "        ServerName $SERVERNAME"  >> /etc/apache2/sites-available/tcat.conf
echo "        $APACHECONF2"  >> /etc/apache2/sites-available/tcat.conf
echo "            Require user $TCATADMINUSER $TCATUSER" >> /etc/apache2/sites-available/tcat.conf
echo "        $APACHECONF3"  >> /etc/apache2/sites-available/tcat.conf
a2dissite 000-default
a2ensite tcat.conf
cp /var/www/dmi-tcat/config.php.example /var/www/dmi-tcat/config.php
htpasswd -b -c /etc/apache2/passwords $TCATUSER $TCATPASS
sed -i "s/define(\"ADMIN_USER\", \"admin\");/define(\"ADMIN_USER\", \"$TCATADMINUSER\");/g" /var/www/dmi-tcat/config.php
htpasswd -b /etc/apache2/passwords $TCATADMINUSER $TCATADMINPASS
chown $SHELLUSER:$WEBGROUP /etc/apache2/passwords
a2enmod rewrite
/etc/init.d/apache2 restart

echo ""
tput bold
echo "Configuring MySQL server for TCAT ..."
tput sgr0
echo ""

echo "CREATE DATABASE IF NOT EXISTS twittercapture DEFAULT CHARACTER SET utf8mb4 DEFAULT COLLATE utf8mb4_unicode_ci;" | mysql -u$DBUSER  -p$DBPASS
echo "GRANT CREATE, DROP, LOCK TABLES, ALTER, DELETE, INDEX, INSERT, SELECT, UPDATE, CREATE TEMPORARY TABLES ON twittercapture.* TO '$TCATMYSQLUSER'@'localhost' IDENTIFIED BY '$TCATMYSQLPASS';" | mysql -u$DBUSER -p$DBPASS
echo "FLUSH PRIVILEGES;" | mysql -u$DBUSER -p$DBPASS
sed -i "s/dbuser = \"\"/dbuser = \"$TCATMYSQLUSER\"/g" /var/www/dmi-tcat/config.php
sed -i "s/dbpass = \"\"/dbpass = \"$TCATMYSQLPASS\"/g" /var/www/dmi-tcat/config.php
sed -i "s/example.com\/dmi-tcat\//$SERVERNAME\//g" /var/www/dmi-tcat/config.php

if [ "$URLEXPANDYES" == "y" ]; then
   echo ""
   tput bold
   echo "Installation and configuration of the URL expander ..."
   tput sgr0
   echo ""
   apt-get install -y build-essential libevent-dev python-all-dev python-mysqldb python-setuptools python-pip
   easy_install greenlet
   easy_install gevent 
   pip install requests
   CRONLINE="0 *     * * *   $SHELLUSER   (cd /var/www/dmi-tcat/helpers; sh urlexpand.sh)"
   echo "" >> /etc/cron.d/tcat
   echo "# Run DMI-TCAT URL expander every hour" >> /etc/cron.d/tcat
   echo "$CRONLINE" >> /etc/cron.d/tcat
fi

echo ""
tput bold
echo "Activating TCAT controller in cron ..."
tput sgr0
echo ""

CRONLINE="* *     * * *   $SHELLUSER   (cd /var/www/dmi-tcat/capture/stream/; php controller.php)"
echo "" >> /etc/cron.d/tcat
echo "# Run TCAT controller every minute" >> /etc/cron.d/tcat
echo "$CRONLINE" >> /etc/cron.d/tcat

echo ""
tput bold
echo "Setting up logfile rotation ..."
tput sgr0
echo ""

read -d '' LOGROTATE <<"EOF"
/var/www/dmi-tcat/logs/controller.log /var/www/dmi-tcat/logs/track.error.log /var/www/dmi-tcat/logs/follow.error.log /var/www/dmi-tcat/logs/onepercent.error.log  
{ 
   weekly  
   rotate 8  
   compress  
   delaycompress  
   missingok  
   ifempty
EOF
echo "$LOGROTATE" > /etc/logrotate.d/dmi-tcat
echo "   create 644 $SHELLUSER $SHELLGROUP"  >> /etc/logrotate.d/dmi-tcat
echo "}" >> /etc/logrotate.d/dmi-tcat

echo ""
echo "You are ready for the final configuration steps of TCAT."
echo "========================================================"
echo ""
echo "Please select the primary capture role of this TCAT instance."
echo ""
echo "1) Track phrases and keywords"
echo "2) Follow Twitter users"
echo "3) Capture a one percent sample of all Twitter traffic"
echo ""
echo "Enter your choice:"
INPUT=0
while [ $INPUT -ne 1 ] && [ $INPUT -ne 2 ] && [ $INPUT -ne 3 ]; do
   read INPUT
   # Make this an integer, and non-empty for bash
   INPUT=${INPUT//[^[:digit:]]/1}
   INPUT=${INPUT//^$/1}
   if [ $INPUT -eq 1 ]; then
        echo "Using role: track"
   elif [ $INPUT -eq 2 ]; then
        echo "Using role: follow"
        sed -i "s/array(\"track\")/array(\"follow\")/g" /var/www/dmi-tcat/config.php
   elif [ $INPUT -eq 3 ]; then
        echo "Using role: onepercent"
        sed -i "s/array(\"track\")/array(\"onepercent\")/g" /var/www/dmi-tcat/config.php
   else
        echo "Unrecognized input. Please try again."
   fi
done
echo ""
echo "You need to have a set of Twitter API keys to be able to capture tweets. These keys can be created through: https://apps.twitter.com/"
echo ""
read -p "Paste your applications consumer key: " CONSUMERKEY
read -p "Paste your applications consumer secret: " CONSUMERSECRET
read -p "Paste your applications user token: " USERTOKEN
read -p "Paste your applications user scret: " USERSECRET
echo ""
sed -i "s/^\$twitter_consumer_key = \"\";/\$twitter_consumer_key = \"$CONSUMERKEY\";/g" /var/www/dmi-tcat/config.php
sed -i "s/^\$twitter_consumer_secret = \"\";/\$twitter_consumer_secret = \"$CONSUMERSECRET\";/g" /var/www/dmi-tcat/config.php
sed -i "s/^\$twitter_user_token = \"\";/\$twitter_user_token = \"$USERTOKEN\";/g" /var/www/dmi-tcat/config.php
sed -i "s/^\$twitter_user_secret = \"\";/\$twitter_user_secret = \"$USERSECRET\";/g" /var/www/dmi-tcat/config.php

# Check if the current MySQL configuration is the system default one
CHANGEDMYCNF=`debsums -ce | grep -c -e "/etc/mysql/my.cnf"`
if [ "$CHANGEDMYCNF" == "0" ]; then
    echo ""
    read -p "Would you like me to autoconfigure your MySQL servers memory profile (recommended only for single-purpose TCAT servers) ([y]es/[n]o)?" YESNO
    while [ "$YESNO" != "y" ] && [ "$YESNO" != "n" ]; do
        echo "Unrecognized input. Please enter y or n"
        read YESNO
    done
    if [ "$YESNO" == "y" ]; then
        echo ""
        tput bold
        echo "Attempting to adjust MySQL server profile ..."
        tput sgr0
        echo ""
        MAXMEM=`free -m | head -n 2 | tail -n 1 | tr -s ' ' | cut -d ' ' -f 2`
        # Make this an integer, and non-empty for bash
        MAXMEM=${MAXMEM//[^[:digit:]]/0}
        MAXMEM=${MAXMEM//^$/0}
        echo "Maximum machine memory detected: $MAXMEM Mb"
        if [ "$MAXMEM" -lt "1024" ]; then
            echo "This machine has a limited ammount of memory; leaving system defaults in place."
        else
            echo "[mysqld]" > /etc/mysql/conf.d/tcat-autoconfigured.cnf
            # Set the key buffer to 1/3 of system memory
            SIZE=$(($MAXMEM/3))
            echo "key_buffer              = $SIZE""M" >> /etc/mysql/conf.d/tcat-autoconfigured.cnf
            if [ "$MAXMEM" -gt "1024" ]; then
                # Set the query cache limit to 128 Mb
                echo "query_cache_limit       = 128M" >> /etc/mysql/conf.d/tcat-autoconfigured.cnf
            else
                # For machines with 1G memory or less, set the query cache limit to 64 Mb
                echo "query_cache_limit       = 64M" >> /etc/mysql/conf.d/tcat-autoconfigured.cnf
            fi
            # Set the total query cache size to 1/8 of systemn emory
            SIZE=$(($MAXMEM/8))
            echo "query_cache_size        = $SIZE""M" >> /etc/mysql/conf.d/tcat-autoconfigured.cnf
            # Increase sizes of temporary tables (memory sort tables for doing a GROUP BY) for machines with sufficient memory
            if [ "$MAXMEM" -gt "7168" ]; then
                echo "tmp_table_size          = 1G" >> /etc/mysql/conf.d/tcat-autoconfigured.cnf
                echo "max_heap_table_size     = 1G" >> /etc/mysql/conf.d/tcat-autoconfigured.cnf
            elif [ "$MAXMEM" -gt "3072" ]; then
                echo "tmp_table_size          = 256M" >> /etc/mysql/conf.d/tcat-autoconfigured.cnf
                echo "max_heap_table_size     = 256M" >> /etc/mysql/conf.d/tcat-autoconfigured.cnf
            fi
            # Unless we have a machine capable of performing many heavy queries simultaneously,
            # it is sensible to restrict the maximum number of client connections. This will reduce the overcommitment of memory.
            # The default max_connections for MySQL 5.6 is 150. In any case, even 80 is still a high figure.
            if [ "$MAXMEM" -lt "31744" ]; then
                echo "max_connections         = 80" >> /etc/mysql/conf.d/tcat-autoconfigured.cnf
            fi
            echo "Memory profile adjusted"
            # Finally, reload MySQL server configuration
            echo "Restarting service ... "
            /etc/init.d/mysql restart
        fi
    fi
fi

echo ""
tput bold
echo "Done!"
tput sgr0
echo ""

echo "Please visit your new TCAT installation at: http://$SERVERNAME/capture/"
echo "Log in using your web-frontend admnistrator credentials."
echo ""
echo "The following steps are recommended, but not mandatory"
echo ""
echo " * Set-up your systems e-mail (sendmail)"
echo ""