#!/bin/bash
# Licensed Materials - Property of IBM
# IBM Sterling Order Management (5725-D10), IBM Order Management (5737-D18)
# (C) Copyright IBM Corp. 2020 All Rights Reserved.
# US Government Users Restricted Rights - Use, duplication or disclosure restricted by GSA ADP Schedule Contract with IBM Corp.

echo " =============== Starting instance/db initialization ==============="
date
su - db2inst1 -c "db2set DB2_CAPTURE_LOCKTIMEOUT=OFF"
su - db2inst1 -c "db2set DB2_SKIPINSERTED=ON"
su - db2inst1 -c "db2set DB2_USE_ALTERNATE_PAGE_CLEANING=ON"
su - db2inst1 -c "db2set DB2_NUM_CKPW_DAEMONS=0"
su - db2inst1 -c "db2set DB2_EVALUNCOMMITTED=ON"
su - db2inst1 -c "db2set DB2_SELECTIVITY=ON"
su - db2inst1 -c "db2set DB2_SKIPDELETED=ON"
su - db2inst1 -c "db2set DB2LOCK_TO_RB=STATEMENT"
su - db2inst1 -c "db2set DB2COMM=tcpip"
su - db2inst1 -c "db2set DB2_PARALLEL_IO=ON"
su - db2inst1 -c "db2set DB2_NUM_CKPW_DAEMONS=0"
su - db2inst1 -c "db2set DB2_COMPATIBILITY_VECTOR=ORA"
su - db2inst1 -c "db2set DB2_DEFERRED_PREPARE_SEMANTICS=NO"

update_db()
{
	su - db2inst1 -c "db2 update db cfg for $DB_DATA using SELF_TUNING_MEM ON"
	su - db2inst1 -c "db2 update db cfg for $DB_DATA using LOGFILSIZ 102400"
	su - db2inst1 -c "db2 update db cfg for $DB_DATA using LOGPRIMARY 10"
	su - db2inst1 -c "db2 update db cfg for $DB_DATA using LOGSECOND 100"
}

su - db2inst1 -c "db2 connect to $DB_DATA"
if [ $? -ne 0 ]; then
    date
    if [ "$DB_BACKUP_RESTORE" = "true" ] && [ -f "/var/oms/$DB_BACKUP_FILE" ] && [ "$DB_IMPORTDATA" != "true" ]; then
		DB_BACKUP_NAME=$(basename "/var/oms/$DB_BACKUP_FILE" ".tar.gz")
		cd /tmp
		rm -rf $DB_BACKUP_NAME
		tar xzf /var/oms/$DB_BACKUP_FILE
		echo "Restoring database $DB_DATA from /tmp/$DB_BACKUP_NAME"
		date
		chmod -R 777 /tmp/$DB_BACKUP_NAME
		su - db2inst1 -c "db2 -x 'RESTORE DATABASE $DB_DATA FROM /tmp/$DB_BACKUP_NAME REPLACE EXISTING'"
		rm -rf /tmp/$DB_BACKUP_NAME
		echo "$DB_DATA restored...."
    else
		echo "Creating new database $DB_DATA"
		date
	    su - db2inst1 -c "db2 -x 'CREATE DATABASE $DB_DATA'"
		echo "Configuring database $DB_DATA"
        su - db2inst1 -c "db2 -x 'connect to $DB_DATA' && db2 -x 'CREATE BUFFERPOOL OMS32K_BP IMMEDIATE SIZE AUTOMATIC PAGESIZE 32k' && db2 -x 'CREATE BUFFERPOOL OMS_TMP_32K_BP IMMEDIATE SIZE AUTOMATIC PAGESIZE 32k' && db2 -x 'CREATE TABLESPACE OMS_32K_TS PAGESIZE 32k MANAGED BY AUTOMATIC STORAGE BUFFERPOOL OMS32K_BP' && db2 -x 'CREATE TEMPORARY TABLESPACE OMS_TMP_32K_TS PAGESIZE 32k MANAGED BY AUTOMATIC STORAGE BUFFERPOOL OMS_TMP_32K_BP' && db2 -x 'GRANT USE OF TABLESPACE OMS_32K_TS to public'"
		update_db
        echo "$DB_DATA configured...."
        if [ "$DB_IMPORTDATA" = "true" ]; then
        	cd /tmp
        	rm -rf db2move
        	cp -a /tmp/oms/db2move .
        	chmod -R 777 db2move
        	su - db2inst1 -c "db2 -x 'connect to $DB_DATA' && cd /tmp/db2move && db2 -tvf db2look.sql && db2move $DB_DATA import" 
        fi
    fi
fi
update_db
su - db2inst1 -c "db2 disconnect ALL"
su - db2inst1 -c "db2stop force"
su - db2inst1 -c "db2start"
touch /var/oms/db.ready
echo " =============== Instance/db initialization done ==============="
date
