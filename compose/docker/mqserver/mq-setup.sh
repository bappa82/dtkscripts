#!/bin/bash
# Licensed Materials - Property of IBM
# IBM Sterling Order Management (5725-D10), IBM Order Management (5737-D18)
# (C) Copyright IBM Corp. 2020 All Rights Reserved.
# US Government Users Restricted Rights - Use, duplication or disclosure restricted by GSA ADP Schedule Contract with IBM Corp.

if [ "$LICENSE" = "accept" ]; then
echo "License accepted ...."
  #exit 0
elif [ "$LICENSE" = "view" ]; then
  case "$LANG" in
    zh_TW*) LICENSE_FILE=Chinese_TW.txt ;;
    zh*) LICENSE_FILE=Chinese.txt ;;
    cs*) LICENSE_FILE=Czech.txt ;;
    en*) LICENSE_FILE=English.txt ;;
    fr*) LICENSE_FILE=French.txt ;;
    de*) LICENSE_FILE=German.txt ;;
    el*) LICENSE_FILE=Greek.txt ;;
    id*) LICENSE_FILE=Indonesian.txt ;;
    it*) LICENSE_FILE=Italian.txt ;;
    ja*) LICENSE_FILE=Japanese.txt ;;
    ko*) LICENSE_FILE=Korean.txt ;;
    lt*) LICENSE_FILE=Lithuanian.txt ;;
    pl*) LICENSE_FILE=Polish.txt ;;
    pt*) LICENSE_FILE=Portuguese.txt ;;
    ru*) LICENSE_FILE=Russian.txt ;;
    sl*) LICENSE_FILE=Slovenian.txt ;;
    es*) LICENSE_FILE=Spanish.txt ;;
    tr*) LICENSE_FILE=Turkish.txt ;;
    *) LICENSE_FILE=English.txt ;;
  esac
  cat /opt/mqm/licenses/$LICENSE_FILE
  exit 1
else
  echo -e "Set environment variable LICENSE=accept to indicate acceptance of license terms and conditions.\n\nLicense agreements and information can be viewed by running this image with the environment variable LICENSE=view.  You can also set the LANG environment variable to view the license in a different language."
exit 1
fi

if [ -L "/var/mqm" ]; then
    echo "/var/mqm is already a symlink."
    /opt/mqm/bin/crtmqdir -a -f
  else
    if [ -d "/mnt/mqm/" ]; then
      DATA_DIR=/mnt/mqm/data
      MOUNT_DIR=/mnt/mqm
      echo "Symlinking /var/mqm to $DATA_DIR"

      # Add mqm to the root user group and add group permissions to mount directory
      #usermod -aG root mqm
      #chmod 775 ${MOUNT_DIR}

      if [ ! -e ${DATA_DIR} ]; then
        mkdir -p ${DATA_DIR}
        chown mqm:mqm ${DATA_DIR}
        chmod 775 ${DATA_DIR}
      fi

      /opt/mqm/bin/crtmqdir -a -f
     cp -RTnv /var/mqm /mnt/mqm/data

      # Remove /var/mqm and replace with a symlink
      rm -rf /var/mqm
      ln -s ${DATA_DIR} /var/mqm
      chown -h mqm:mqm /var/mqm
    else
      # Create the MQ data Directory
      /opt/mqm/bin/crtmqdir -a -f
    fi
fi

#Configure the console 
cp /mnt/mqm/data/web/installations/Installation1/servers/mqweb/mqwebuser.xml /mnt/mqm/data/web/installations/Installation1/servers/mqweb/mqwebuser_backup.xml
cat <<EOF > /mnt/mqm/data/web/installations/Installation1/servers/mqweb/mqwebuser.xml
<?xml version="1.0" encoding="UTF-8"?>
<server>
    <featureManager>
        <feature>appSecurity-2.0</feature>
        <feature>basicAuthenticationMQ-1.0</feature>
    </featureManager>
    <enterpriseApplication id="com.ibm.mq.console">
        <application-bnd>
            <security-role name="MQWebAdmin">
                <group name="MQWebUI" realm="defaultRealm"/>
            </security-role>
            <security-role name="MQWebAdminRO">
                <user name="reader" realm="defaultRealm"/>
            </security-role>
        </application-bnd>
    </enterpriseApplication>
    <enterpriseApplication id="com.ibm.mq.rest">
        <application-bnd>
            <security-role name="MQWebAdmin">
                <group name="MQWebUI" realm="defaultRealm"/>
            </security-role>
        </application-bnd>
    </enterpriseApplication>
    <basicRegistry id="basic" realm="defaultRealm">
        <user name="admin" password="passw0rd"/>
        <user name="reader" password="p@ssword"/>
        <group name="MQWebUI">
            <member name="admin"/>
        </group>
    </basicRegistry>
    <variable name="httpHost" value="*"/>
    <httpDispatcher enableWelcomePage="false" appOrContextRootMissingMessage='Redirecting to console.&lt;script&gt;document.location.href="/ibmmq/console";&lt;/script&gt;' />
    <sslDefault sslRef="mqDefaultSSLConfig"/>
</server>
EOF

#start MQ console
setmqweb properties -k mqConsoleAutostart -v true
setmqweb properties -k mqRestAutostart -v true
strmqweb &

echo "---------MQ console setup and started------------"
source /opt/mqm/bin/setmqenv -s
dspmqver
echo "Checking filesystem..."
amqmfsck /var/mqm

QMGR_EXISTS=`dspmq | grep ${MQ_QMGR_NAME} > /dev/null ; echo $?`

if [ ${QMGR_EXISTS} -ne 0 ]; then
  echo "Creating qmgr"
  MQ_DEV=${MQ_DEV:-"false"}
  if [ "${MQ_DEV}" == "true" ]; then
    # Turns on early adopt if we're using Developer defaults
    export AMQ_EXTRA_QM_STANZAS=Channels:ChlauthEarlyAdopt=Y
  fi
  crtmqm -q ${MQ_QMGR_NAME} || true
fi


strmqm  ${MQ_QMGR_NAME}
dspmq -m ${MQ_QMGR_NAME} 
echo "--------- Qmgr started ------------"

set +e
for MQSC_FILE in $(ls -v /etc/mqm/*.mqsc); do
  runmqsc ${MQ_QMGR_NAME} < ${MQSC_FILE}
done
set -e
echo "--------- Qmgr configured ------------"
