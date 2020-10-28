#!/bin/bash
# Licensed Materials - Property of IBM
# IBM Sterling Order Management (5725-D10), IBM Order Management (5737-D18)
# (C) Copyright IBM Corp. 2020 All Rights Reserved.
# US Government Users Restricted Rights - Use, duplication or disclosure restricted by GSA ADP Schedule Contract with IBM Corp.

mkdir -p /opt/mqscripts
cp -a /tmp/oms/* /opt/mqscripts
chmod +x /opt/mqscripts/*
chmod -R 777 $MQ_JNDI_DIR/
chmod 777 $MQ_JNDI_DIR/.bindings

echo "----------- MQ setup started -----------"

su - mqm -c "export MQ_QMGR_NAME=$MQ_QMGR_NAME && export LICENSE=$LICENSE && source /opt/mqscripts/mq-setup.sh"

source /opt/mqscripts/mq-bindings.sh configure
chmod 777 $MQ_JNDI_DIR/.bindings

echo "----------- MQ setup complete -----------"

while true; do sleep 1000; done
