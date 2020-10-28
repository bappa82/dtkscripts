#!/bin/bash
# Licensed Materials - Property of IBM
# IBM Sterling Order Management (5725-D10), IBM Order Management (5737-D18)
# (C) Copyright IBM Corp. 2018, 2020 All Rights Reserved.
# US Government Users Restricted Rights - Use, duplication or disclosure restricted by GSA ADP Schedule Contract with IBM Corp.

set -o allexport
. /tmp/oms/.env
set +o allexport

backup()
{
rm -rf /var/oms/${DB_BACKUP_FILE}
if [[ "$DB_BACKUP_RESTORE" = "true" ]] && [[ $1 == setup ]] ; then
	if [[ ! -f "$DB_BACKUP_DIR/$DB_BACKUP_FILE" ]]; then
		echo "Error: db backup file $DB_BACKUP_DIR/$DB_BACKUP_FILE not found!!!"
		exit 1
	fi
	echo "DB_BACKUP_RESTORE mode enabled. Copying $DB_BACKUP_DIR/$DB_BACKUP_FILE to /var/oms ..."
	cp -a $DB_BACKUP_DIR/$DB_BACKUP_FILE /var/oms
fi
}

ks_check()
{
echo "Check/wait for app keystore file ..."
t=120
while [ $t -gt 0 ]; do
	if [ -f /var/oms/keystore/key.jks ]; then
        echo "Keystore file found. Proceed..."
		break
	else
		let t='t-1'
		sleep 10s
	fi
done
if [ $t -eq 0 ]; then
	echo "Error: Keystore not created even after 20 minutes. Check appserver settings and logs at 'docker logs -f om-appserver'. This can also occur because of slowness of your machine or docker subsystem."
	exit 1
fi
}

db_check()
{
echo "Waiting for DB to start (including database creation first time). You can run 'docker logs -f om-db2server' in new window in the mean while to see the db container log..."
date
T=360
if [[ $1 == "setup" ]] && [[ "$DB_IMPORTDATA" = "true" ]]; then
	echo "Since you are importing data, this may take longer than what it takes for fresh setup process ..."
	T=720
fi
t=$T
while [ $t -ge 0 ]; do
	if [ -f /var/oms/db.ready ]; then
		break
	else
		let t='t-1'
		sleep 10s
	fi
done
if [ $t -eq 0 ]; then
	echo "Error: DB didn't start even after ${T}0 seconds. Check DB settings and logs at 'docker logs -f om-db2server'. This can also occur because of slowness of your machine or docker subsystem."
	exit 1
fi
ts=`expr $T - $t`
tss=`expr 10 \* $ts`
echo "DB started! Took $tss seconds."
}

process()
{
UPGRADE=""
if [[ $1 == "setup-upg" ]] || [[ "$DB_IMPORTDATA" = "true" ]]; then
	UPGRADE="upgrade"
fi

export DPM=$(cat $RT/properties/sandbox.cfg | grep "^DATABASE_PROPERTY_MANAGEMENT=" | head -n1 | cut -d'=' -f2)
echo "DATABASE_PROPERTY_MANAGEMENT==$DPM"
cp -a /tmp/oms/safestart.properties ${RT}/properties
sed -i "s/DB_HOST/${DB_HOST_IMAGE}/g;s/DB_PORT/${DB_PORT_IMAGE}/g;s/DB_DATA/${DB_DATA}/g;s/DB_USER/${DB_USER}/g;s/DB_PASS/${DB_PASS}/g;s/DB_SCHEMA_OWNER/${DB_SCHEMA_OWNER}/g" ${RT}/properties/safestart.properties
cat ${RT}/properties/past_system_defaults.properties > ${RT}/properties/system_overrides.properties
echo "" >> ${RT}/properties/system_overrides.properties
cat ${RT}/properties/present_system_defaults.properties >> ${RT}/properties/system_overrides.properties

mkdir -p ${RT}/tmp
cd ${RT}/bin

if [[ "$DB_BACKUP_RESTORE" = "true" ]] && [[ $1 == "setup" ]] && [[ "$DB_IMPORTDATA" != "true" ]]; then
    echo "Running entitydeployer post DB restore..."
    ./deployer.sh -t entitydeployer -l info -Dapplysqlonly=true
    if [[ $? == 1 ]]; then exit 1; fi
    
	echo "Loading properties post DB restore ..."
	./loadProperties.sh -skipdb N -validateDBPropMgmt N
else
	if [[ $1 == setup* ]] && [[ $OM_IGNORE_DB_RELOAD != "true" ]]; then
		echo "Running entitydeployer ..."
		./deployer.sh -t entitydeployer -l info -Dapplysqlonly=true
		if [[ $? == 1 ]]; then exit 1; fi
	  
        echo "Loading properties ..."
		./loadProperties.sh -skipdb N -validateDBPropMgmt N
		
		echo "Loading FC..."
		cd ${RT}/repository/factorysetup && find . -name "*.restart" -exec rm -rf {} \; && cd ${RT}/bin
        ./loadFactoryDefaults.sh $UPGRADE
        if [[ $? == 1 ]]; then exit 1; fi
		cd ${RT}/repository/factorysetup && find . -name "*.restart" -exec rm -rf {} \; && cd ${RT}/bin
		
		echo "Loading Views..."
		./loadCustomDB.sh $UPGRADE
	fi
fi

if [[ $1 == setup* ]]; then
	if [[ -f "${RT}/properties/past_system_defaults.properties" ]] && [[ $1 == "setup" ]]; then
		echo "Loading past_system_defaults.properties to DB ..."
		./manageProperties.sh -mode import -file "${RT}/properties/past_system_defaults.properties"
	fi
	if [[ -f "${RT}/properties/present_system_defaults.properties" ]]; then
		echo "Loading present_system_defaults.properties to DB ..." 
		./manageProperties.sh -mode import -file "${RT}/properties/present_system_defaults.properties"
	fi
fi

if [[ ${OM_INSTALL_LOCALIZATION} = "true" ]] && [[ ! -z "$OM_LOCALES" ]]; then
	echo "Setting up localization for locales - $OM_LOCALES ..."
	var=$( echo "$OM_LOCALES" | tr ',' ' ')
	for LOCALE in ""$var""
	do
		echo "Loading for locale: $LOCALE"
		./loadDefaults.sh ../repository/factorysetup/complete_installation/${LOCALE}_locale_installer.xml ../repository/factorysetup/complete_installation/XMLS
	done
	echo "Loading Language Pack translations ..."
	./sci_ant.sh -f localizedstringreconciler.xml import -Dsrc=$RT/repository/factorysetup/complete_installation/XMLS -Dbasefilename=ycplocalizedstrings
	./sci_ant.sh -f localizedstringreconciler.xml import -Dsrc=$RT/repository/factorysetup/isccs/XMLS -Dbasefilename=isccsliterals2translate
	./sci_ant.sh -f localizedstringreconciler.xml import -Dsrc=$RT/repository/factorysetup/wsc/XMLS -Dbasefilename=wscliterals2translate
	./sci_ant.sh -f localizedstringreconciler.xml import -Dsrc=$RT/repository/factorysetup/sfs/XMLS -Dbasefilename=sfsliterals2translate
fi

CUST_JAR=`echo "$(ls /tmp/oms/custjar/* 2>/dev/null)" |head -n1`
if [ ! -z "$CUST_JAR" ]; then 
	echo "Installing custommization jar $CUST_JAR ..."
    disable_dpm
	./InstallService.sh $CUST_JAR -skipJavadocs
	if [[ $? == 1 ]]; then
    	enable_dpm
    	exit 1
    fi
	./deployer.sh -t resourcejar
	./deployer.sh -t entitydeployer -l info
    if [[ $? == 1 ]]; then
    	enable_dpm
    	exit 1
    else
    	enable_dpm
    fi
fi
#if [[ -f "${RT}/properties/customer_overrides.properties" ]]; then
#	echo "Loading customer_overrides.properties to DB..." 
#	./manageProperties.sh -mode import -file "${RT}/properties/customer_overrides.properties"
#fi
integrate_services $1
if [[ $? == 1 ]]; then exit 1; fi
setup_store
if [[ $? == 1 ]]; then exit 1; fi
build_ear
if [[ $? == 1 ]]; then exit 1; fi
}


build_ear()
{
echo "Building EAR for $AP_WAR_FILES ..."
rm -rf $RT/external_deployments/*
ADDNL_OPTS=""
if [[ $AP_SKIP_ANGULAR_MINIFICATION = "true" ]]; then
	ADDNL_OPTS="$ADDNL_OPTS -Dskipangularminification=true"
fi

cd ${RT}/bin
./buildear.sh $ADDNL_OPTS -Dappserver=websphere -Dwarfiles=${AP_WAR_FILES} -Ddevmode=${AP_DEV_MODE} -Dnowebservice=true -Dnoejb=true -Dnodocear=true -Dwebsphere-profile=liberty
if [[ $? == 1 ]]; then exit 1; fi
echo "Exploding smcfs.ear ..."
cd  ${RT}/external_deployments
mv smcfs.ear smcfs.ear1
mkdir smcfs.ear
cd smcfs.ear
$RT/jdk/bin/jar xf ../smcfs.ear1
rm -rf ../smcfs.ear1
rm -rf META_INF
if [[ ! -d lib ]]; then
	mkdir lib
	mv *.jar lib
fi
if [[ ! -z $AP_EXPLODED_WARS ]]; then
	var=$( echo "$AP_EXPLODED_WARS" | tr ',' ' ')
	cd  ${RT}/external_deployments/smcfs.ear
	for i in $var; do 
		echo "Exploding $i ..." 
		if [ -f $i ]; then 
			mv $i ${i}1 && mkdir $i && cd $i && $RT/jdk/bin/jar xf ../${i}1 && cd ../ && rm -rf ${i}1 
			#cd $i && rm -rf META-INF && mv WEB-INF/lib/* ../lib/ && cd ../
		else
			echo "$i not found. Skipping ..."
		fi
	done
fi
if [[ ! -z $AP_EXPLODED_BEJARS ]]; then
	var=$( echo "$AP_EXPLODED_BEJARS" | tr ',' ' ')
	cd  ${RT}/external_deployments/smcfs.ear/lib
	for i in $var; do 
		echo "Exploding $i ..." 
		if [ -f $i ]; then 
			mv $i ${i}1 && mkdir $i && cd $i && $RT/jdk/bin/jar xf ../${i}1 && cd ../ && rm -rf ${i}1 
		else
			echo "$i not found. Skipping ..."
		fi
	done
fi
if [[ $AP_EXPLODED_EAR != "true" ]]; then
	echo "Packing smcfs.ear ..."
	cd  ${RT}/external_deployments/smcfs.ear
	$RT/jdk/bin/jar cMf ../smcfs.ear1 *
	cd ../
	rm -rf smcfs.ear
	mv smcfs.ear1 smcfs.ear
fi

echo "Cleaning tmp directory ..."
rm -rf ${RT}/tmp/*

echo "Runtime initialized."
}

extract-rt()
{
	rm -rf ${RT}/../test
	mkdir -p ${RT}/../test
	if [[ $1 == "extract-rt-props" ]]; then
        mkdir -p ${RT}/../test/runtime
        cd ${RT}/../test/runtime
        mkdir -p bin properties
        cd ${RT}/properties
        cp -a safestart.properties sandbox.cfg ${RT}/../test/runtime/properties
	else
        cd ${RT}/../
        rsync -aq runtime test --exclude "tmp/*" --exclude "external_deployments/*" --exclude "installed_data/*" --exclude "repository/entitybuild/*"
	fi
	cd ${RT}/../test/runtime
	grep -rl "${RT}" bin | xargs sed -i "s#${RT}#${RTH}#g"
	grep -rl "${RT}" properties | xargs sed -i "s#${RT}#${RTH}#g"
	#grep -rl "${RT2}" bin | xargs sed -i "s#${RT2}#${RTH}#g"
	sed -i "s/${DB_HOST_IMAGE}:${DB_PORT_IMAGE}/${DB_HOST}:${DB_PORT}/g" properties/safestart.properties
}

integrate_services()
{
	if [[ $IV_ENABLE == 'Y' ]]; then
        echo "Enabling IV integration"
	
		sed -i "s/IV_TENANTID/${IV_TENANTID}/g;s/IV_CLIENTID/${IV_CLIENTID}/g;s/IV_SECRET/${IV_SECRET}/g;s#IV_BASEURL#${IV_BASEURL}#g" ${RT}/properties/safestart.properties

		sed -i "s#MQ_JNDI_DIR#${MQ_JNDI_DIR2}#g;s/IV_DEMAND_QUEUE/${IV_DEMAND_QUEUE}/g;s/IV_SUPPLY_QUEUE/${IV_SUPPLY_QUEUE}/g;s/MQ_CONNECTION_FACTORY_NAME/${MQ_CONNECTION_FACTORY_NAME}/g" ${RT}/properties/safestart.properties
		
        if [[ $IV_PHASE1 == 'Y' ]]; then
            sed -i "s/iv_integration./#iv_integration./g" ${RT}/properties/safestart.properties
            if [[ $1 == setup* ]] && [[ ! -z $IV_PHASE1_ENTERPRISE ]]; then
                echo "Installing IV Adapter Phase 1 activator for enterprise $IV_PHASE1_ENTERPRISE"
                iv_phase1_activator $IV_PHASE1_ENTERPRISE
                if [[ $? == 1 ]]; then exit 1; fi
            fi
        else
            disable_dpm
            cd ${RT}/bin
            ./sci_ant.sh -f configureIVIntegration.xml -DNewCustomerImplementation=true
    		if [[ $? == 1 ]]; then
        		enable_dpm
       			exit 1
    		else
    			enable_dpm
    		fi
        fi
        
        SET_INTEGRATION=Y
    fi
    if [[ $SIM_ENABLE == 'Y' ]]; then
        echo "Enabling SIM integration"
        sed -i "s/SIM_ENABLE/Y/g;s/SIM_TENANTID/${SIM_TENANTID}/g;s/SIM_CLIENTID/${SIM_CLIENTID}/g;s/SIM_SECRET/${SIM_SECRET}/g;s/JWT_PK_ALIAS/${JWT_PK_ALIAS}/g;s#SIM_ENDPOINTURL#${SIM_ENDPOINTURL}#g;s#IV_ENDPOINTURL#${IV_ENDPOINTURL}#g" ${RT}/properties/safestart.properties
        SET_INTEGRATION=Y
    fi
    if [[ $SET_INTEGRATION == 'Y' ]]; then    
        sed -i "s/DTK_ID/${DTK_ID}/g" ${RT}/properties/safestart.properties
        export AJD=$(cat $RT/properties/sandbox.cfg | grep "^AGENT_JAVA_DEFINES=")
        export AJD1=$(cat $RT/properties/sandbox.cfg | grep "^AGENT_JAVA_DEFINES=-Djavax.net.ssl.keyStore")
        if [ -z "$AJD" ]; then 
            echo "AGENT_JAVA_DEFINES=-Djavax.net.ssl.keyStore=key.jks -Djavax.net.ssl.keyStorePassword=secret4ever -Djavax.net.ssl.trustStore=key.jks -Djavax.net.ssl.trustStorePassword=secret4ever -Dcom.ibm.jsse2.overrideDefaultTLS=true" >> $RT/properties/sandbox.cfg
        elif [ -z "$AJD1" ]; then
            sed -i "s#AGENT_JAVA_DEFINES=#AGENT_JAVA_DEFINES=-Djavax.net.ssl.keyStore=key.jks -Djavax.net.ssl.keyStorePassword=secret4ever -Djavax.net.ssl.trustStore=key.jks -Djavax.net.ssl.trustStorePassword=secret4ever -Dcom.ibm.jsse2.overrideDefaultTLS=true #g" $RT/properties/sandbox.cfg
        fi
        cd ${RT}/bin
        ./setupfiles.sh
	fi
}

iv_phase1_activator()
{
    cd ${RT}/repository/factorysetup && find . -name "*.restart" -exec rm -rf {} \; && cd ${RT}/bin
    disable_dpm
    ./sci_ant.sh -f integration_load_defaults.xml -DFunctionality=SIV -DEnterpriseCode=$1 -DIV_CLIENT_ID=${IV_CLIENTID} -DIV_SECRET=${IV_SECRET} -DTenant_ID=${IV_TENANTID} overrideinstall
    if [[ $? == 1 ]]; then
        enable_dpm
        exit 1
    else
    	enable_dpm
    fi
}

setup_store()
{
	cd ${RT}/bin
	if [[ $STORE_DISABLE_LEGACY_APP == 'N' ]]; then
		echo "Enabling DOJO Store"
		./sci_ant.sh -f storeSetup.xml enable-legacy-store
		if [[ $? == 1 ]]; then exit 1; fi
		./setupfiles.sh
		echo "DOJO Store Enabled"
	elif [[ $STORE_DISABLE_LEGACY_APP == 'Y' ]]; then
		echo "Disabling DOJO Store"
		./sci_ant.sh -f storeSetup.xml disable-legacy-store
		if [[ $? == 1 ]]; then exit 1; fi
		./setupfiles.sh
		echo "DOJO Store Disabled"
	fi
}

disable_dpm()
{
	sed -i "s/DATABASE_PROPERTY_MANAGEMENT=true/DATABASE_PROPERTY_MANAGEMENT=false/g" $RT/properties/sandbox.cfg
}

enable_dpm()
{
	sed -i "s/DATABASE_PROPERTY_MANAGEMENT=false/DATABASE_PROPERTY_MANAGEMENT=true/g" $RT/properties/sandbox.cfg
}

case $1 in
    backup|ks_check|db_check|iv_phase1_activator)
        $1 "$2"
    ;;
	setup|setup-upg|update-extn)
		process "$1"
	;;
	extract-rt|extract-rt-props)
		extract-rt "$1"
	;;
	*)
	echo "'$1' is not a supported argument."
esac
