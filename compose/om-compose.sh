#!/bin/bash
# Licensed Materials - Property of IBM
# IBM Sterling Order Management (5725-D10), IBM Order Management (5737-D18)
# (C) Copyright IBM Corp. 2018, 2020 All Rights Reserved.
# US Government Users Restricted Rights - Use, duplication or disclosure restricted by GSA ADP Schedule Contract with IBM Corp.

export D=$(cd `dirname $0` && pwd)
export PD=$(dirname $D)
T=`date +%Y_%m_%d_%H_%M_%S`
set -o allexport
. $D/docker/docker-compose.properties
if [[ -f $D/docker/integration.properties ]]; then
    . $D/docker/integration.properties
fi
if [[ -f $D/docker/om-tag.properties ]]; then
    . $D/docker/om-tag.properties
fi
if [[ -f $D/om-compose.properties ]]; then
    . $D/om-compose.properties
fi
set +o allexport

display_license(){
    echo -e "$OM_PROD - License information coming up. Press Enter to continue ..."
    read -p ""
	more $D/LICENSE.txt
	echo -e "\n${LIC_STMT}${OM_LIC} or files under license directory. Press Enter to continue ..."
	read -p ""
	echo -e "\n$DB_PROD"
	echo -e "\n${LIC_STMT}${DB_LIC}. Press Enter to continue ..."
	read -p ""
	echo -e "\n$AP_PROD"
	echo -e "\n${LIC_STMT}${AP_LIC}. Press Enter to continue ..."
	read -p ""
	echo -e "\n$MQ_PROD"
	echo -e "\n${LIC_STMT}${MQ_LIC}. Press Enter to continue ..."
	read -p ""
}

show_license(){
	if [ "$DTK_LICENSE" == "accept" ]; then
		echo "DTK_LICENSE explicitely set to 'accept'. This means you have read and accept all license agreements. Proceeding ..."
	else
		display_license
		
		name="requestion"
		count=0
		while [[ "$name" = "requestion" &&  $count -lt 10 ]]
		do
		  echo -e "\n\nIf you accept the license agreements, enter 'accept': "
		  read -p "" name
		  name=${name:-requestion}
		  count=$((count + 1))
		done
		
		if [ "$name" == "accept" ]; then
            export DTK_LICENSE=accept
            echo -e "\nYou have accepted the license agreements. Setup is proceeding ...\n\n"
            sleep 1
		else
            echo -e "\nError: You have not accepted the license agreements. Setup is exiting.\n"
            exit 1
		fi
	fi
}

if [[ $1 == setup* ]] && [[ $3 != "--accept" ]]; then
	show_license
fi

if [[ $1 == "license" ]]; then
    display_license
else
	mkdir -p logs/backups
	if [ -f "logs/om-compose_${1}.log" ]; then
		mv logs/om-compose_${1}.log logs/backups/om-compose_${1}.log.$T
	fi
	if [ -f "logs/om-compose_${1}_db.log" ]; then
		mv logs/om-compose_${1}_db.log logs/backups/om-compose_${1}_db.log.$T
	fi
	if [ -f "logs/om-compose_${1}_mq.log" ]; then
		mv logs/om-compose_${1}_mq.log logs/backups/om-compose_${1}_mq.log.$T
	fi
	if [ -f "logs/om-compose_${1}_ap.log" ]; then
		mv logs/om-compose_${1}_ap.log logs/backups/om-compose_${1}_ap.log.$T
	fi
	exec 1> >(tee -a logs/om-compose_${1}.log)
	exec 2>&1
	echo "$(date) - $1 $2 $3 $4 $5" >> logs/xhistory.log
fi

check_custjar()
{
	if [[ $1 = "update-extn" ]]; then
		if [ ! -f "$2" ]; then 
			echo "NOTE: No customization package jar provided as argument."
		fi
	fi
	rm -rf $D/docker/omruntime/custjar
	if [[ -f "$2" ]]; then 
		mkdir -p $D/docker/omruntime/custjar
		cp -a ${2} $D/docker/omruntime/custjar
	fi
}

check_safestart()
{
	if [[ ! -f $D/docker/omruntime/safestart.properties ]]; then
        cp -a $D/docker/omruntime/safestart.properties.sample $D/docker/omruntime/safestart.properties
    fi
}

rem_old_for_upg()
{
	rem_old_om_for_upg
	rem_old_om_image
	rem_old_ap_for_upg
	rem_old_ear_for_upg
	rem_old_mq_for_upg
	rem_old_db_for_upg
}

rem_old_om_for_upg()
{
	echo "Removing old om-runtime contaner if exists ..."
	oorc=$(docker ps -a -f "name=om-runtime" -q)
	if [[ ! -z $oorc ]]; then
		echo "Removing old om-runtime container- $oorc..."
		docker rm om-runtime -f
	fi
}

rem_old_om_image()
{
    echo "Removing old om-runtime image if exists ..."
	oori=$(docker images $OM_IMAGE:$OM_TAG -q)
	if [[ ! -z $oori ]]; then
		echo "Image/s of $OM_IMAGE:$OM_TAG already exist - $oori . Retagging image with current time and removing current tag ..."
		docker tag $OM_IMAGE:$OM_TAG $OM_IMAGE:${OM_TAG}_$T
		docker rmi $OM_IMAGE:$OM_TAG
	fi
}

rem_old_ap_for_upg()
{
	echo "Removing old om-appserver contaner if exists ..."
	oorc=$(docker ps -a -f "name=om-appserver" -q)
	if [[ ! -z $oorc ]]; then
		echo "Removing old om-appserver container- $oorc..."
		docker rm om-appserver -f
	fi
}

rem_old_ear_for_upg()
{
	echo "Removing old ear volume if exists..."
	docker volume rm -f docker_ear
}

rem_old_mq_for_upg()
{
	echo "Removing old om-mqserver contaner if exists ..."
	oorc=$(docker ps -a -f "name=om-mqserver" -q)
	if [[ ! -z $oorc ]]; then
		echo "Removing old om-mqserver container- $oorc..."
		docker rm om-mqserver -f
	fi
}

rem_old_db_for_upg()
{
	echo "Removing old om-db2server contaner if exists ..."
	oorc=$(docker ps -a -f "name=om-db2server" -q)
	if [[ ! -z $oorc ]]; then
		echo "Removing old om-db2server container- $oorc..."
		docker rm om-db2server -f
	fi
}

load_image()
{
	echo "Loading image..."
	if [[ ! "$(docker images -q $OM_IMAGE:$OM_TAG)" ]]; then
        export OM_TAG_OLD=$OM_TAG
		if [[ -f "$OM_IMAGE_FILE" ]]; then
			echo "Loading image from file $OM_IMAGE_FILE ..."
			docker load --input $OM_IMAGE_FILE
		else
			echo "Could not find image file $OM_IMAGE_FILE. Checking for any ${OM_IMAGE}_*.tar.gz file in compose parent dir (latest will be picked if multiple files present)..."
			FF=$(ls -rt $PD/${OM_IMAGE}_*.tar.gz | tail -1)
			F=${FF#*${OM_IMAGE}_}
			F=${F%\.tar.gz}
			echo "Found file $FF. Tag evaluated from file to $F"
			export OM_TAG=$F
            oori=$(docker images $OM_IMAGE:$OM_TAG -q)
            if [[ -z $oori ]]; then
                export OM_IMAGE_FILE=$FF
                if [[ -f "$OM_IMAGE_FILE" ]]; then
                    echo "Loading image from file $OM_IMAGE_FILE ..."
                    docker load --input $OM_IMAGE_FILE
                fi
            fi
		fi
		if [[ ! "$(docker images -q $OM_IMAGE:$OM_TAG)" ]]; then
			echo "Error: Couldnot fetch OM docker image $OM_IMAGE:$OM_TAG. Check your settings for OM_TAG and tar.gz files present."
			exit 1
		else
			echo "Docker image $OM_IMAGE:$OM_TAG loaded successfully."
            if [[ $OM_TAG != $OM_TAG_OLD ]]; then
                echo "OM_TAG=$OM_TAG" > $D/docker/om-tag.properties
                echo "OM_IMAGE_FILE=\$PD/\${OM_IMAGE}_\${OM_TAG}.tar.gz" >> $D/docker/om-tag.properties
            fi
		fi
    fi
}

prep_properties()
{
	echo "PD=$PD" > $D/docker/.env
	echo "D=$D" >> $D/docker/.env
	echo "" >> $D/docker/.env
	cat $D/docker/docker-compose.properties >> $D/docker/.env
	echo "" >> $D/docker/.env
    if [[ -f $D/docker/integration.properties ]]; then
        cat $D/docker/integration.properties >> $D/docker/.env
        echo "" >> $D/docker/.env
    fi
    if [[ -f $D/docker/om-tag.properties ]]; then
        cat $D/docker/om-tag.properties >> $D/docker/.env
        echo "" >> $D/docker/.env
    fi
    if [[ -f $D/om-compose.properties ]]; then
        cat $D/om-compose.properties >> $D/docker/.env
        echo "" >> $D/docker/.env
    fi
    export DTK_LICENSE=accept
	echo "DTK_LICENSE=accept" >> $D/docker/.env
	echo "MQ_JNDI_DIR2=$MQ_JNDI_DIR" >> $D/docker/.env
	cp -a $D/docker/.env $D/docker/omruntime
	if [[ $NETWORK_MODE == "host" ]]; then
        export DCF=docker-compose-host.yml
        cp -a $D/docker/docker-compose.yml $D/docker/$DCF
        RES=$(cat $D/docker/$DCF | grep "network_mode: \"host\"")
        if [[ -z $RES ]]; then
            if [[ $HOST_OS == "mac" ]]; then
                sed -i "" "s|container_name.*|&\n    network_mode: \"host\"|g" $D/docker/$DCF
            else
                sed -i "s|container_name.*|&\n    network_mode: \"host\"|g" $D/docker/$DCF
            fi
        fi
	fi
}

start_stop()
{
	prep_properties
	cd $D/docker
	if [ ! -z $2 ]; then
		if [[ $1 != "start" ]]; then
			docker-compose -f $DCF stop $2
		fi
		if [[ $1 == *start ]]; then
			docker-compose -f $DCF start $2
		fi
	else
		if [[ $1 != "start" ]]; then
			docker-compose -f $DCF stop
		fi
		if [[ $1 == *start ]]; then
			docker-compose -f $DCF start
		fi
	fi
}

wipe_clean()
{
	prep_properties
	echo "Cleaning all volumes and containers ..."
	cd $D/docker 
	docker-compose -f $DCF down -v --remove-orphans
	echo "Cleaning ${MQ_JNDI_DIR}/.bindings and temp files in compose ..."
	rm -rf .env omruntime/.env omruntime/custjar
	rm -rf ${MQ_JNDI_DIR}/.bindings
	echo "Not cleaning any extracted runtime files. Clean them manually."
	rem_old_om_image
}

add_queue()
{
	prep_properties
	if [[ ! -z $2 ]]; then
		DEPTH=$2
	else
		DEPTH=5000
	fi
	if [ $MQ_JNDI_DIR = "../jndi" ]; then export MQ_JNDI_DIR=$PD/jndi ; fi
	docker exec -e Q=$1 -e DEPTH=$DEPTH -u mqm om-mqserver /bin/bash -c 'echo -e "define qlocal ($Q) MAXDEPTH($DEPTH)\nexit" | runmqsc $MQ_QMGR_NAME'
	docker exec om-mqserver sh -c "/opt/mqscripts/mq-bindings.sh update $MQ_JNDI_DIR $1"
}

delete_queue()
{
	prep_properties
	if [[ ! -z $2 ]]; then
		OPTION=$2
	else
		OPTION=NOPURGE
	fi
	if [ $MQ_JNDI_DIR = "../jndi" ]; then export MQ_JNDI_DIR=$PD/jndi ; fi
	docker exec -e Q=$1 -e OPTION=$OPTION -u mqm om-mqserver /bin/bash -c 'echo -e "delete qlocal ($Q) $OPTION\nexit" | runmqsc $MQ_QMGR_NAME'
	docker exec om-mqserver sh -c "/opt/mqscripts/mq-bindings.sh update $MQ_JNDI_DIR $1"
}

import_cert()
{
    CF=$PD/certificates/$1
	if [[ ! -f $CF ]]; then
        echo "Error: Certificate/bundle file invalid. Provide path to certificate/bundle file relative to the devtoolkit_docker/certificates directory."
		exit 1
	fi
	validate_cert_file $1
    if [[ $? == 1 ]]; then exit 1; fi
    for EXT in cer crt p12 ; do
		if [[ $1 == *.$EXT ]]; then
            cert=$(basename "$1" ".$EXT")
        fi
	done
    alias=$2
    if [[ -z $alias ]]; then
        alias=$cert
    fi
    if [[ "$cert" != "$alias" ]]; then
        echo "Error: Either do not pass alias or rename your certificate/bundle file to conform to <alias>.cer or <alias>.crt name, or <alias>.p12 (where alias represents the alias of the private key in the p12 bundle)"
        exit 1
    fi
    docker exec -u root:root om-appserver sh -c "chmod -R 777 /var/oms/keystore/key.jks"
    certfile=$(basename "$1")

    docker cp $CF om-appserver:/tmp
    docker exec -u root:root om-appserver sh -c "chmod -R 777 /tmp/$certfile"
    if [[ $1 == *.cer ]] || [[ $1 == *.crt ]]; then
        echo "Deleting any existing certificate of alias $alias in appserver (ignore error thrown if doesn't exist)"
        docker exec om-appserver sh -c "keytool -delete -noprompt -alias $alias -storepass secret4ever -keystore /var/oms/keystore/key.jks"
        echo "Importing certificate $certfile, alias $alias in appserver"
        docker exec om-appserver sh -c "keytool -import -noprompt -alias $alias -storepass secret4ever -keystore /var/oms/keystore/key.jks -file /tmp/$certfile"
    fi
    if [[ $1 == *.p12 ]]; then
        echo "Importing/overwriting bundle file $certfile, alias $alias in appserver"
        docker exec om-appserver sh -c "keytool -importkeystore -noprompt -srcstorepass secret4ever -deststorepass secret4ever -destkeystore /var/oms/keystore/key.jks -srckeystore /tmp/$certfile -srcstoretype PKCS12"
    fi
    docker exec -u root:root om-appserver sh -c "rm -rf /tmp/$certfile"

    docker exec -u root:root om-runtime sh -c "if [[ ! -f \$RT/bin/key.jks ]]; then echo 'Runtime keystore doesnot exist. Creating at \$RT/bin/key.jks ...' && cd \$RT/jdk/bin && ./keytool -genkey -alias keystore -keyalg RSA -keystore \$RT/bin/key.jks -storepass secret4ever -keypass secret4ever -dname 'CN=keystore' && chmod -R 777 \$RT/bin/key.jks; fi"
    docker cp $CF om-runtime:/tmp
    if [[ $1 == *.cer ]] || [[ $1 == *.crt ]]; then
        echo "Deleting any existing certificate of alias $alias in runtime (ignore error thrown if doesn't exist)"
        docker exec om-runtime sh -c "cd \$RT/jdk/bin && ./keytool -delete -storepass secret4ever -noprompt -alias $alias -keystore \$RT/bin/key.jks"
        echo "Importing certificate $certfile, alias $alias in runtime"
        docker exec om-runtime sh -c "cd \$RT/jdk/bin && ./keytool -import -storepass secret4ever -noprompt -alias $alias -keystore \$RT/bin/key.jks -file /tmp/$certfile"
    fi
    if [[ $1 == *.p12 ]]; then
        echo "Importing/overwriting bundle file $certfile, alias $alias in runtime"
        docker exec om-runtime sh -c "cd \$RT/jdk/bin && ./keytool -importkeystore -noprompt -srcstorepass secret4ever -deststorepass secret4ever -destkeystore \$RT/bin/key.jks -srckeystore /tmp/$certfile -srcstoretype PKCS12"
    fi
    docker exec -u root:root om-runtime sh -c "rm -rf /tmp/$certfile"
    
    if [[ -d $RTH ]]; then
        if [[ ! -f $RTH/bin/key.jks ]]; then 
            echo 'Extracted runtime keystore doesnot exist. Creating at $RTH/bin/key.jks ...' 
            cd $RTH/jdk/bin 
            ./keytool -genkey -alias keystore -keyalg RSA -keystore $RTH/bin/key.jks -storepass secret4ever -keypass secret4ever -dname 'CN=keystore' 
            chmod -R 777 $RTH/bin/key.jks
        fi
        if [[ $1 == *.cer ]] || [[ $1 == *.crt ]]; then
            echo "Deleting any existing certificate of alias $alias in extracted runtime (ignore error thrown if doesn't exist)"
            cd $RTH/jdk/bin 
            ./keytool -delete -storepass secret4ever -noprompt -alias $alias -keystore $RTH/bin/key.jks
            echo "Importing certificate $certfile, alias $alias in extracted runtime"
            ./keytool -import -storepass secret4ever -noprompt -alias $alias -keystore $RTH/bin/key.jks -file $CF
        fi
        if [[ $1 == *.p12 ]]; then
            echo "Importing/overwriting bundle file $certfile, alias $alias in extracted runtime"
            cd $RTH/jdk/bin 
            ./keytool -importkeystore -noprompt -srcstorepass secret4ever -deststorepass secret4ever -destkeystore $RTH/bin/key.jks -srckeystore $CF -srcstoretype PKCS12
        fi
    fi
}

import_one_cert()
{
	prep_properties
	if [[ "$1" == "ALL" ]]; then
        import_all_certs
	else
        import_cert $1 $2
	fi
}

import_all_certs()
{
	printf "\nImporting/overwriting all certificates in $PD/certificates ...\n"
    validate_cert_files
    if [[ $? == 1 ]]; then exit 1; fi
    cd $PD/certificates
    find . -type f -print0 | while IFS= read -r -d $'\0' line; do
        if [[ $line != *\/\.* ]]; then
            import_cert $line
        else
            echo "Ignoring hidden file $line ..."
        fi
    done
    printf "Certificates import finished. \n\n"
}

validate_cert_file()
{
    if [[ $1 != *.cer ]] && [[ $1 != *.crt ]] && [[ $1 != *.p12 ]]; then
        echo "Error: File to import/remove ($1) must be a certificate of the pattern xyz.cer or xyz.crt, where xyz is the alias to be used to register to keystore. It can also be a .p12 bundle."
        return 1
    fi
}

validate_cert_files()
{
    echo "Validating certificates in $PD/certificates ..."
    cd $PD/certificates
    find . -type f -print0 | while IFS= read -r -d $'\0' line; do
        if [[ $line != *\/\.* ]]; then
            echo "Validating $line ..."
            validate_cert_file $line
            if [[ $? == 1 ]]; then exit 1; fi
        else
            echo "Ignoring hidden file $line ..."
        fi
    done
    echo "All certificates in $PD/certificates validated."
    echo ""
}

remove_cert()
{
	if [[ -z $1 ]]; then
        echo "Error: Certfile alias cannot be null"
		exit 1
	fi
	echo "Removing certificate alias $1"
	docker exec -u root:root om-appserver sh -c "chmod -R 777 /var/oms/keystore/key.jks"
	docker exec om-appserver sh -c "keytool -delete -storepass secret4ever -noprompt -alias $1 -keystore /var/oms/keystore/key.jks"
	docker exec om-runtime sh -c "cd \$RT/jdk/bin && ./keytool -delete -storepass secret4ever -noprompt -alias $1 -keystore \$RT/bin/key.jks"
	if [[ -d $RTH ]]; then
        cd $RTH/jdk/bin 
        ./keytool -delete -storepass secret4ever -noprompt -alias $1 -keystore $RTH/bin/key.jks
    fi
}

remove_one_cert()
{
	prep_properties
	if [[ "$1" == "ALL" ]]; then
        remove_all_certs
	else
        remove_cert $1
	fi
}

remove_all_certs()
{
    cd $PD/certificates
    find . -type f -print0 | while IFS= read -r -d $'\0' line; do
        alias=""
    	if [[ $line == *.cer ]]; then
	        alias=$(basename "$line" ".cer")
        fi
    	if [[ $line == *.crt ]]; then
	        alias=$(basename "$line" ".crt")
        fi
    	if [[ $line == *.p12 ]]; then
	        alias=$(basename "$line" ".p12")
        fi
        if [[ ! -z $alias ]]; then
	        remove_cert $alias
        fi
    done
}

list_all_certs()
{
    docker exec om-appserver sh -c "keytool -list -storepass secret4ever -keystore /var/oms/keystore/key.jks"
}

pre_checks()
{
	if [[ $DB_IMPORTDATA == "true" ]]; then
        echo "Validating DB_IMPORTDATA=true mode ..."
        cd $D/docker/db2server
		if [[ ! -f db2move/db2look.sql ]] || [[ ! -f db2move/db2move.lst ]]; then
			echo "Error: db2move/db2look data not found in $D/docker/db2server/db2move, but DB_IMPORTDATA set to true. To create db2move/db2look data from your earlier DB, first run './om-compose.sh export-dbdata' from your earlier devtoolkit_docker/compose directory."
			exit 1
		fi
		if [[ $1 == "setup-upg" ]]; then
			echo "Error: DB_IMPORTDATA=true only supported for setup, not setup-upg, since your database needs to be recreated."
			exit 1
		fi
        echo "Validated ..."
        echo ""
	fi
	check_jdk
	if [[ $? == 1 ]]; then exit 1; fi
	validate_cert_files
	if [[ $? == 1 ]]; then exit 1; fi
	if [[ -z $1 ]]; then
        pre_services "CHECK"
    else
        pre_services
    fi
	if [[ $? == 1 ]]; then exit 1; fi
}

post_checks()
{
	if [[ $1 == setup* ]]; then
		docker logs om-appserver > logs/om-compose_${1}_ap.log
		docker logs om-db2server > logs/om-compose_${1}_db.log
		docker logs om-mqserver > logs/om-compose_${1}_mq.log
	fi
}

export_dbbackup()
{
    docker stop om-appserver
    docker start om-db2server
    export DB_BACKUP=${DB_DATA}_$1
    if [[ -z $1 ]]; then export DB_BACKUP=${DB_DATA} ; fi    	
    rm -rf $D/docker/db2server/${DB_BACKUP}.tar.gz
    docker exec om-db2server sh -c "cd /tmp && rm -rf $DB_BACKUP ${DB_BACKUP}.tar.gz && mkdir -p $DB_BACKUP && chmod 777 $DB_BACKUP"
    docker exec om-db2server sh -c "su - db2inst1 -c 'db2stop force && db2start && sleep 10s && db2 backup db $DB_DATA to /tmp/$DB_BACKUP'"
    docker exec om-db2server sh -c "cd /tmp && tar -czf ${DB_BACKUP}.tar.gz $DB_BACKUP"
    docker cp om-db2server:/tmp/${DB_BACKUP}.tar.gz $D/docker/db2server/${DB_BACKUP}.tar.gz
    docker start om-appserver
}

export_dbdata()
{
    docker start om-db2server
    docker exec om-db2server sh -c "cd /tmp && rm -rf db2move && mkdir -p db2move && chmod 777 db2move"
    docker exec om-db2server sh -c "su - db2inst1 -c 'cd /tmp/db2move && db2move ${DB_DATA} export -sn ${DB_SCHEMA_OWNER}'"
    docker exec om-db2server sh -c "su - db2inst1 -c 'db2look -d ${DB_DATA} -e -z ${DB_SCHEMA_OWNER} -o /tmp/db2move/db2look.sql'"
    cd $D/docker/db2server
    rm -rf db2move
    mkdir -p db2move && cd db2move
    docker cp om-db2server:/tmp/db2move/. .
    ###### Uncomment to achieve further tuning of db2move by discarding tables with no rows - Start ######
    # mv db2move.lst db2move_full.lst
    # while read p; do
    #     A=$(echo $p | cut -d'!' -f4) 
    #     B=$(echo $A | cut -d'.' -f1)
    #     G=$(cat $A | grep 'exporting \"0\" rows')
    #     if [[ -z $G ]]; then
    #         echo $p >> db2move.lst
    #     else
    #         rm $B.msg $B.ixf
    #     fi
    # done < db2move_full.lst
    ###### Uncomment to achieve further tuning of db2move by discarding tables with no rows - End ########
}

extract_appman() 
{
	cd $RTH/bin
	rm -rf ../ApplicationManagerClient
	./sci_ant.sh -f buildApplicationManagerClient.xml -Dlibdir=lib -Drunnable-jar=client.jar -Dpackagezip=AppManager.zip
	cd ../ApplicationManagerClient
	APP_ZIP=$(ls *.zip)
	../jdk/bin/jar xf ${APP_ZIP}
}

extract_runtime() 
{
	prep_properties
	extract_rt
}

check_jdk()
{
	if [[ $HOST_OS = "mac" ]]; then
        echo "Validating jdk for $HOST_OS ..."
        if [[ ! -d $JAVA_HOME ]]; then
            echo "Error: Set JAVA_HOME to jdk directory for $HOST_OS"
            exit 1
		fi
		if [[ ! -f $JAVA_HOME/bin/java ]] || [[ ! -d $JAVA_HOME/jre/lib ]]; then
            echo "Error: Could not find $JAVA_HOME/bin/java or $JAVA_HOME/jre/lib"
            exit 1
		fi
		$JAVA_HOME/bin/java -version
		A=$?
        if [[ $A != 0 ]]; then
            echo "Error: Could not run '$JAVA_HOME/bin/java -version' successfully. Check if JAVA_HOME is properly set."
            exit 1
        fi
        JAVA_DIR=$(echo $JAVA_HOME | grep -o "\/User\/.*\/Library\/Java")
        echo "JAVA_DIR resolved as '$JAVA_DIR' ..."
        if [[ -d $JAVA_DIR ]]; then
            echo "Creating $JAVA_DIR/Extensions ..."
            mkdir -p $JAVA_DIR/Extensions
        fi
        echo ""
	fi
}

extract_rt() 
{
	date
	check_jdk
	if [[ $? == 1 ]]; then exit 1; fi
	echo "Cleaning old host runtime files (renaming $RTH if exisits) ..."
	if [[ -d $RTH ]]; then
		mv $RTH ${RTH}_$T
		printf "Renamed existing host runtime directory to runtime_$T. Delete this if you don't want it anymore.\n\n"
	fi
	echo "Extracting runtime files to host runtime directory $RTH (this can take time) ..."
	docker exec om-runtime sh -c "/tmp/oms/init_runtime.sh extract-rt"
	echo "Files prepared on runtime container ..."
	date
    mkdir -p $RTH
    docker cp om-runtime:$RT/../test/runtime/. $RTH/
    docker exec om-runtime sh -c "rm -rf $RT/../test"
	cd $RTH
	chmod +x bin/* jdk/bin/* jdk/jre/bin/*
	echo "Files extracted on host machine ..."
	date
	if [[ $HOST_OS = "mac" ]]; then
		echo "Replacing jdk from $JAVA_HOME for HOST_OS=mac ..."
		mv jdk jdku
		cp -a $JAVA_HOME jdk
		cp -a jdku/jre/lib/endorsed jdk/jre/lib
		chmod -R +x jdk/bin/ jdk/jre/bin/
	fi
	cd $RTH/bin
	./setupfiles.sh
	./deployer.sh -t resourcejargen
	extract_appman
	echo "Extracting runtime files to host runtime directory $RTH complete."
	date
}

extract_rt_props() 
{
    check_rt
    echo "Extracting system files to host runtime directory $RTH  ..."
    docker exec om-runtime sh -c "/tmp/oms/init_runtime.sh extract-rt-props"
    docker cp om-runtime:$RT/../test/runtime/. $RTH/
    cd $RTH/bin
    ./setupfiles.sh
}

start_server()
{
    check_rt
    cd $RTH/bin
    if [[ -z $2 ]]; then
        echo "Error: Server name must be passed"
        exit 1
    fi
    ./setupfiles.sh
    if [[ ! -z $3 ]]; then
        export DEBUG_ARGS_SUSPEND=n
        if [[ $4 = "Y" ]] || [[ $4 = "y" ]]; then
            export DEBUG_ARGS_SUSPEND=y
        fi
        export DEBUG_ARGS="-Xdebug -Xrunjdwp:transport=dt_socket,server=y,address=${3},suspend=${DEBUG_ARGS_SUSPEND}"
    fi
    if [[ $1 = "start-agent" ]]; then
        if [[ ! -z $3 ]]; then
            sed -i "s#-Dvendor=#${DEBUG_ARGS} -Dvendor=#g" $RTH/bin/agentserver.sh
        fi
        ./agentserver.sh $2
    elif [[ $1 = "start-intg" ]]; then
        if [[ ! -z $3 ]]; then
            sed -i "s#-Dvendor=#${DEBUG_ARGS} -Dvendor=#g" $RTH/bin/./startIntegrationServer.sh
        fi
        ./startIntegrationServer.sh $2
    fi
}

install_ri() 
{
	check_rt
	cd $RTH/bin
	./InstallService.sh ../referenceImplementation/ReferenceImpl.jar -skipJavadocs
	./sci_ant.sh -f ycd_load_oms_ref_impl.xml -Drunmasterdata=Y
}

check_rt()
{
    if [[ ! -d $RTH ]]; then
        echo "Error: Host runtime directory not found at $RTH. To get runtime directory on host, first run './om-compose.sh extract-rt'"
        exit 1
    fi
}

mqjc_setup()
{
    JDK_HOME=$RTH/jdk
    if [[ ! -f $JDK_HOME/bin/javac ]]; then
        JDK_HOME=$JAVA_HOME
    fi
    if [[ ! -f $JDK_HOME/bin/javac ]]; then
        echo "Error: javac not found in $JDK_HOME/bin"
        exit 1
    fi
    if [[ ! -f $JDK_HOME/bin/keytool ]]; then
        echo "Error: keytool not found in $JDK_HOME/bin"
        exit 1
    fi
    if [[ ! -f $1 ]]; then
        echo "Error: Private key (.p12 file) not passed, or doesn't exist $1"
        exit 1
    fi
    PKF=$(basename $1)
    PKEXT=${PKF#*.}
    if [[ $PKEXT != "p12" ]] && [[ $PKEXT != "P12" ]]; then
        echo "Error: Passed file has to be a .p12 file - $1"
        exit 1
    fi
    echo -n "Enter private key password:"
    read -s PKPASS
    echo
    
    rm -rf $MQJC_DIR
    mkdir -p $MQJC_DIR/pkey
    cp -a $1 $MQJC_DIR/pkey
    cd $MQJC_DIR
    mkdir -p classes certs lib
    cp -a $D/docker/mqserver/mqjc/lib/* lib/
    cp -a $D/docker/mqserver/mqjc/certs/* certs/
    
    cd $D/docker/mqserver/mqjc/src
    find -name "*.java" > $MQJC_DIR/classes/sources.txt
    echo "Compiling ... $(cat $MQJC_DIR/classes/sources.txt)"
    $JDK_HOME/bin/javac -cp "$MQJC_DIR/lib/*" -d $MQJC_DIR/classes @$MQJC_DIR/classes/sources.txt
    if [[ $? != 0 ]]; then 
        echo "Error: Could not compile MQ Java Client classes in $D/docker/mqserver/mqjc/src. Setup has failed."
        exit 1
    fi
    rm $MQJC_DIR/classes/sources.txt
    
    for F in "$MQJC_DIR/certs"/* ; do
        FILE=$(basename $F)
        EXT=${FILE#*.}
        NAME=$(basename $F ".$EXT")
        echo "Importing FILE=$FILE EXT=$EXT NAME=$NAME ..."
        $JDK_HOME/bin/keytool -import -noprompt -alias $NAME -file $F -keystore $MQJC_DIR/certs/trustStore.jks -storepass secret4ever -storetype jks
        if [[ $? != 0 ]]; then 
            echo "Error: Could not import certificate $F into truststore. Setup has failed."
            exit 1
        fi
    done
    
    cd $MQJC_DIR/certs
    $JDK_HOME/bin/keytool -importkeystore -srckeystore $MQJC_DIR/pkey/$PKF -srcstorepass $PKPASS -srcstoretype pkcs12 -destkeystore keystore.jks -deststorepass $PKPASS -deststoretype jks
    if [[ $? != 0 ]]; then 
        echo "Error: Could not import $PKF into keystore. Check the p12 file passed, or the password entered. Setup has failed."
        exit 1
    fi
}

mqjc(){
    JDK_HOME=$RTH/jdk
    if [[ ! -f $JDK_HOME/bin/java ]]; then
        JDK_HOME=$JAVA_HOME
    fi
    if [[ ! -f $JDK_HOME/bin/java ]]; then
        echo "Error: java not found in $RTH/jdk or $JAVA_HOME"
        exit 1
    fi
    echo -n "Enter private key password:"
    read -s PKPASS
    echo
    
    PROPS=${@:1}
    echo "Input props: $PROPS"    
    if [[ $PROPS != *DMQJC_HOST* ]] && [[ ! -z $MQJC_HOST ]]; then
        PROPS="$PROPS -DMQJC_HOST=$MQJC_HOST"
    fi
    if [[ $PROPS != *DMQJC_PORT* ]] && [[ ! -z $MQJC_PORT ]]; then
        PROPS="$PROPS -DMQJC_PORT=$MQJC_PORT"
    fi
    if [[ $PROPS != *DMQJC_CHANNEL* ]] && [[ ! -z $MQJC_CHANNEL ]]; then
        PROPS="$PROPS -DMQJC_CHANNEL=$MQJC_CHANNEL"
    fi
    if [[ $PROPS != *DMQJC_QMGR* ]] && [[ ! -z $MQJC_QMGR ]]; then
        PROPS="$PROPS -DMQJC_QMGR=$MQJC_QMGR"
    fi
    if [[ $PROPS != *DMQJC_QUEUE* ]] && [[ ! -z $MQJC_QUEUE ]]; then
        PROPS="$PROPS -DMQJC_QUEUE=$MQJC_QUEUE"
    fi
    if [[ $PROPS != *DMQJC_CIPHER* ]] && [[ ! -z $MQJC_CIPHER ]]; then
        PROPS="$PROPS -DMQJC_CIPHER=$MQJC_CIPHER"
    fi
    if [[ $PROPS != *DMQJC_RETRY_INTERVAL* ]] && [[ ! -z $MQJC_RETRY_INTERVAL ]]; then
        PROPS="$PROPS -DMQJC_RETRY_INTERVAL=$MQJC_RETRY_INTERVAL"
    fi
    if [[ $PROPS != *DMQJC_RETRY_NUM* ]] && [[ ! -z $MQJC_RETRY_NUM ]]; then
        PROPS="$PROPS -DMQJC_RETRY_NUM=$MQJC_RETRY_NUM"
    fi
    echo "Final props: $PROPS"
    
    ORAJAVA=$($JDK_HOME/bin/java -version 2>&1 | grep "Java HotSpot")
    echo $ORAJAVA
    if [[ ! -z $ORAJAVA ]]; then
        echo "You are using Java Hotspot VM from Oracle"
        CIPHERPROP="-Dcom.ibm.mq.cfg.useIBMCipherMappings=false"
        if [[ $PROPS == *DMQJC_CIPHER* ]] && [[ $PROPS != *DMQJC_CIPHER=TLS_* ]]; then
            echo "Error: Cipher passed/set must start with TLS_"
            exit 1
        fi
    fi
    
    IBMJAVA=$($JDK_HOME/bin/java -version 2>&1 | grep "IBM J9")
    echo $IBMJAVA
    if [[ ! -z $IBMJAVA ]]; then
        echo "You are using Java IBM J9 VM from IBM"
        CIPHERPROP=""
        if [[ $PROPS == *DMQJC_CIPHER* ]] && [[ $PROPS != *DMQJC_CIPHER=SSL_* ]]; then
            echo "Error: Cipher passed/set must start with SSL_"
            exit 1
        fi
    fi
    
    cd $MQJC_DIR
    $JDK_HOME/bin/java -cp "$MQJC_DIR/classes:$MQJC_DIR/lib/*" $CIPHERPROP -Djavax.net.ssl.trustStore=certs/trustStore.jks -Djavax.net.ssl.trustStorePassword=secret4ever -Djavax.net.ssl.keyStore=certs/keystore.jks -Djavax.net.ssl.keyStorePassword=$PKPASS $PROPS $MQJC_CLIENT
}

exec_rt()
{
	docker exec om-runtime sh -c "/tmp/oms/init_runtime.sh $1 $2"
    if [[ $? == 1 ]]; then exit 1; fi
}

build_and_run()
{
	date
	pre_checks $1
	if [[ $? == 1 ]]; then exit 1; fi
	mkdir -p ${MQ_JNDI_DIR} $PD/certificates
	if [[ $1 == setup* ]]; then
		if [[ $1 == "setup" ]]; then
			wipe_clean
			cd $D
		fi
		if [[ $1 == "setup-upg" ]]; then
			rem_old_for_upg
		fi
		load_image
        if [[ $? == 1 ]]; then exit 1; fi
	fi
	if [[ $1 == "update-extn" ]] && [[ $3 != "--skip-initrt" ]] && [[ $REM_RT_CONT_ON_UPD = "true" ]]; then
		rem_old_om_for_upg
	fi
	check_safestart
	check_custjar $1 $2
	
	find . -type f -iname "*.sh" -exec chmod +x {} \;
	prep_properties
	omqc=$(docker ps -a -f "name=om-mqserver" -q)
	oorc=$(docker ps -a -f "name=om-runtime" -q)

	echo "Starting services in no-recreate mode ..."
	cd $D/docker
	if [[ ! -z $oorc ]]; then docker-compose -f $DCF stop omruntime; fi
	if [[ $1 == setup* ]]; then
        echo "Pulling latest middleware images ..."
        docker-compose -f $DCF pull db2server appserver mqserver
    fi
	docker-compose -f $DCF up -d --remove-orphans --no-recreate
	if [[ -f $D/docker/db2server/$DB_BACKUP_FILE ]] && [[ $1 == setup ]]; then
        echo "Will restore custom backup $D/docker/db2server/$DB_BACKUP_FILE ..."
        docker cp $D/docker/db2server/$DB_BACKUP_FILE om-db2server:/var/oms/${DB_BACKUP_FILE}
    else
		exec_rt backup $1
        if [[ $? == 1 ]]; then exit 1; fi
    fi
	exec_rt ks_check
    if [[ $? == 1 ]]; then exit 1; fi
    
    import_all_certs
	start_stop stop appserver
	exec_rt  db_check $1
	if [[ $1 == setup* ]]; then
		start_stop restart db2server
        exec_rt db_check $1
        if [[ $? == 1 ]]; then exit 1; fi
	fi
	
	if [[ $3 != "--skip-initrt" ]]; then
		exec_rt $1
        if [[ $? == 1 ]]; then exit 1; fi
	fi
	post_services
	exec_rt db_check $1
    if [[ $? == 1 ]]; then exit 1; fi
	start_stop restart appserver
	date
	if [[ $1 == setup* ]] && [[ $SKIP_EXTRACTRT_ON_SETUP != "true" ]]; then
		extract_rt
	fi
	if [[ $1 == "update-extn" ]] && [[ -d $RTH ]] && [[ $3 != "--skip-initrt" ]]; then
        extract_rt_props
	fi
	echo "$COMP_LOG"
	if [[ $IV_ENABLE == 'Y' ]] || [[ $SIM_ENABLE == 'Y' ]]; then
		echo "$SERV_LOG"
	fi
	post_checks
}

pre_services()
{
    if [[ $IV_ENABLE == 'Y' ]] || [[ $SIM_ENABLE == 'Y' ]]; then
		check_dtk_id
		if [[ $? == 1 ]]; then exit 1; fi
    fi
	TO_CMD="timeout"
	if [[ $HOST_OS = "mac" ]]; then
        TO_CMD="gtimeout"
    fi
    to_cmd=$(which $TO_CMD)
    TO_CMD="$TO_CMD 20s"
    printf "Timeout command is - $to_cmd\n"
    if [[ -z $to_cmd ]]; then
        TO_CMD=
    fi
	if [[ $IV_ENABLE == 'Y' ]]; then
        if [[ $IV_TENANTID == "" || $IV_CLIENTID == "" || $IV_SECRET == "" || $IV_BASEURL == "" ]]; then
            echo "Error: Please enter the TenantID, ClientID, Secret and Base URL for IV integration"
            exit 1
		else
			echo "All IV integration properties are provided. Attempting to connect to IV cloud instance ..."
		fi
		IV_HOST=$(echo "$IV_BASEURL" | awk -F/ '{print $3}')
		echo -n | $TO_CMD openssl s_client -servername $IV_HOST -connect $IV_HOST:443 -showcerts | sed -ne '/-BEGIN CERTIFICATE-/,/-END CERTIFICATE-/p' > $PD/tempcert.crt
		var=$(cat $PD/tempcert.crt | grep "BEGIN CERTIFICATE")
		if [[ -z $var ]]; then
            echo "Error: IV cloud instance could not be connected. Check connectivity to $IV_HOST."
            exit 1
        else
            echo "IV cloud instance connected successfully!"
        fi
        if [[ $1 != "CHECK" ]]; then
            IV_CERT_DIR=$PD/certificates/iv
            mkdir -p $IV_CERT_DIR
            cp -a $PD/tempcert.crt $IV_CERT_DIR/iv_dtk.crt
            echo "IV certificate extracted from $IV_HOST:443 to $IV_CERT_DIR/iv_dtk.crt"
        fi
        echo ""
        rm -rf $PD/tempcert.crt
    else
        echo "IV is not enabled."
	fi
    if [[ $SIM_ENABLE == 'Y' ]]; then
        if [[ $SIM_IV_ENABLE == 'Y' ]] && [[ $IV_ENABLE != "Y" ]]; then
            echo "Error: IV must be enabled for SIM integration"
            exit 1
		fi
		if [[ $SIM_NONCLOUD_INST == 'Y' ]]; then
            echo "Performing SIM integration with a non-cloud instance ..."
            if [[ $SIM_ENDPOINTURL == "" ]]; then
                echo "Error: Please enter SIM endpoint URL for non-cloud SIM integration"
                exit 1
            fi
		else
            if [[ $SIM_TENANTID == "" || $SIM_CLIENTID == "" || $SIM_SECRET == "" || $SIM_ENDPOINTURL == "" || $JWT_PK_ALIAS == "" ]]; then
                echo "Error: Please enter SIM tenantid, clientid, secret, SIM endpoint URL, JWT private key alias for SIM integration"
                exit 1
            fi
            echo "All SIM integration properties are provided. Attempting to connect to SIM cloud instance ..."
            SIM_HOST=$(echo "$SIM_ENDPOINTURL" | awk -F/ '{print $3}')
            echo -n | $TO_CMD openssl s_client -servername $SIM_HOST -connect $SIM_HOST:443 -showcerts | sed -ne '/-BEGIN CERTIFICATE-/,/-END CERTIFICATE-/p' > $PD/tempcert.crt
            var=$(cat $PD/tempcert.crt | grep "BEGIN CERTIFICATE")
            if [[ -z $var ]]; then
                echo "Error: SIM cloud instance could not be connected. Check connectivity to $SIM_HOST."
                exit 1
            else
                echo "SIM cloud instance connected successfully!"
            fi
            if [[ $1 != "CHECK" ]]; then
                SIM_CERT_DIR=$PD/certificates/sim
                mkdir -p $SIM_CERT_DIR
                cp -a $PD/tempcert.crt $SIM_CERT_DIR/sim_dtk.crt
                echo "SIM certificate extracted from $SIM_HOST:443 to $SIM_CERT_DIR/sim_dtk.crt"
            fi
            echo ""
            rm -rf $PD/tempcert.crt
		fi
    else
        echo "SIM is not enabled."
	fi
}

check_dtk_id()
{
	if [[ $DTK_ID == "" ]]; then
		echo "Error: Devtoolkit environment ID (DTK_ID) not set in your devtoolkit_docker/compose/docker/integration.properties. Please check that you have the latest devtoolkit_extras.tar file with DTK_ID set. If not, re-download your devtoolkit_extras.tar file, which is now updated with DTK_ID information."
		echo "How to check: "
		echo " - For users with a customer-code (OMoC customers), you will find: DTK_ID=oms-<3/5_char_customer-code>-dtk-<dtk_sl_no>"
		echo " - For users without a customer-code (other users), you will find: DTK_ID=oms-gen-<16_char_random_string>"
		exit 1
	else
		printf "Devtoolkit environment ID is $DTK_ID\n\n"
	fi
}

iv_phase1_activator()
{
    if [[ $IV_ENABLE == 'Y' ]]; then
        if [[ $IV_PHASE1 == 'Y' ]]; then
            if [[ -z $1 ]]; then
                echo "Error: Enterprise code must be passed"
                return 1
            fi
            docker exec om-runtime sh -c "/tmp/oms/init_runtime.sh iv_phase1_activator $1"
            if [[ $? == 1 ]]; then exit 1; fi
        else
            echo "Error: Property IV_PHASE1 must be set to Y"
            return 1
        fi
    else
        echo "Error: IV not enabled"
        return 1
    fi
}

post_services()
{
	if [[ $IV_ENABLE == 'Y' ]]; then
        add_queue $IV_DEMAND_QUEUE
        add_queue $IV_SUPPLY_QUEUE
	fi
}

case $1 in
	setup)
		build_and_run "setup" "$2" "$3"
	;;
	setup-upg)
		build_and_run "setup-upg" "$2" "$3"
	;;
	update-extn)
		build_and_run "update-extn" "$2" "$3"
	;;
	start|restart|stop)
		start_stop "$1" "$2"
	;;
	wipe-clean)
		wipe_clean
	;;
	add-queue)
		add_queue "$2" "$3"
	;;
	delete-queue)
		delete_queue "$2" "$3"
	;;
	import-cert)
		import_one_cert "$2" "$3"
	;;    
	remove-cert)
		remove_one_cert "$2"
	;;      
	list-certs)
		list_all_certs
	;; 
	extract-rt)
		start_stop restart omruntime
		extract_runtime
	;;
	extract-rt-props)
		extract_rt_props
	;;
	integrate-services)
		echo "Deprecated!!! Run 'update-extn' instead."
	;;
	check-services)
		pre_services "CHECK"
	;;
	install-ri)
		install_ri
	;;
	validate)
		pre_checks
	;;
	mqjc-setup)
		mqjc_setup $2
	;;
	mqjc)
		mqjc ${@:2}
	;;
	export-dbbackup)
		export_dbbackup $2
	;;
	export-dbdata)
		export_dbdata
	;;
	extract-appman)
		extract_appman
	;;
	start-agent|start-intg)
		start_server "$1" "$2" "$3" "$4"
	;;
	iv-phase1-activator)
		iv_phase1_activator $2
	;;
	license)
		echo -e "\nFinished showing all license information.\n"
	;;
	*)
	prep_properties
	echo "'$1' is not a supported argument. Valid arguments (<o:xyz> means optional argument): "
	echo " setup <o:cust_jar>               Setup a fresh new docker based integrated OM environment"
	echo " setup-upg <o:cust_jar>           Upgrade your existing environment to new images"
	echo " update-extn <o:cust_jar>         Update your OM environment with the latest customization jar"
	echo " extract-rt                       Extracts a copy of runtime on your host machine in devtoolkit_docker"
	echo " start <o:service>                Start your docker environments - all or specific service"
	echo " stop <o:service>                 Stop your docker environments - all or specific service"
	echo " restart <o:service>              Restart your docker environments - all or specific service"
	echo " wipe-clean                       Wipes clean all your containers, including any volume data"
	echo " add-queue <name> <o:depth>       Adds a local queue with provided depth (default 5000)"
	echo " delete-queue <name> <o:option>   Deletes a local queue with PURGE/NOPURGE option (default NOPURGE)"
	echo " import-cert <certfile> <alias>   Import certificate providing cert file path and alias"
	echo " remove-cert <alias>              Remove certificate providing alias"
	echo " list-certs                       List all certificates currently present in the keystore"
    echo " check-services                   Test connectivity to integrated Cloud services (IV/SIM/etc)"
    echo " iv-phase1-activator <entcode>    Installs IV phase1 activator for the given enterprise"
    echo " start-agent <server> <o:port> <o:y>  Start agent server with optional debug port and option to suspend by passing Y/y"
    echo " start-intg <server> <o:port> <o:y>   Start integration server with optional debug port and option to suspend by passing Y/y"
    echo " export-dbdata                    Exports data from your DB2 database by running db2look and db2move utilities"
	echo " extract-appman                   Extracts just Application manager on your host machine runtime"
	echo " validate                         Run pre-validations before setup, etc"
	echo " license                          Shows the license information for various middleware images pulled"
esac
