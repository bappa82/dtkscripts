#!/bin/bash
# Licensed Materials - Property of IBM
# IBM Sterling Order Management (5725-D10), IBM Order Management (5737-D18)
# (C) Copyright IBM Corp. 2020 All Rights Reserved.
# US Government Users Restricted Rights - Use, duplication or disclosure restricted by GSA ADP Schedule Contract with IBM Corp.

if   [ "$1" = "configure" ]; then
	echo -e "def qcf($MQ_CONNECTION_FACTORY_NAME) qmgr($MQ_QMGR_NAME) tran(client) chan(SYSTEM.ADMIN.SVRCONN) port($MQ_PORT) host($MQ_HOST)  " > /tmp/crt_bindings.txt
	for i in {1..10}; do echo -e "define q(DEV.QUEUE.${i}) qu(DEV.QUEUE.${i}) qmgr($MQ_QMGR_NAME)" >> /tmp/crt_bindings.txt ; done
	
	echo -e "END" >> /tmp/crt_bindings.txt

	sed -i "s|PROVIDER_URL=.*|PROVIDER_URL=file://${MQ_JNDI_DIR}|g" /opt/mqm/java/bin/JMSAdmin.config
	/opt/mqm/java/bin/JMSAdmin -v </tmp/crt_bindings.txt
	chmod 777 ${MQ_JNDI_DIR}/.bindings
	
	echo "MQ Server configured successfully. Ignore any 'Unable to bind object javax.naming.NameAlreadyBoundException' errors as they mean queues already exist. "
elif [ "$1" = "update" ]; then
	echo "Updating bindings for queue $3 ..."
	echo -e "define q($3) qu($3) qmgr(OM_QMGR)
	END" > /tmp/upd_bindings.txt
	/opt/mqm/java/bin/JMSAdmin -v  </tmp/upd_bindings.txt
	chmod 777 $2/.bindings
else
    echo "'$1' is not a supported argument."
fi
