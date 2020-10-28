#!/bin/bash
# Licensed Materials - Property of IBM
# IBM Sterling Order Management (5725-D10), IBM Order Management (5737-D18)
# (C) Copyright IBM Corp. 2020 All Rights Reserved.
# US Government Users Restricted Rights - Use, duplication or disclosure restricted by GSA ADP Schedule Contract with IBM Corp.

date
echo "Initializing DB2 ..."
rm -rf /var/oms/db.ready
chage -I -1 -m 0 -M 99999 -E -1 db2inst1
su - db2inst1 -c "db2stop force"
su - db2inst1 -c "db2start"
if   [ $? -ne 0 ]; then
    . /var/db2_setup/lib/setup_db2_instance.sh
else
    . /var/custom/create_database.sh
    while true; do sleep 1000; done
fi
