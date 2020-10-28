/*******************************************************************************
 * IBM Confidential
 * OCO Source Materials
 * IBM Sterling Order Management (5725-D10), IBM Order Management (5737-D18)
 * (C) Copyright IBM Corp. 2020  All Rights Reserved.
 * The source code for this program is not published or otherwise divested of its trade secrets, irrespective of what has been deposited with the U.S. Copyright Office.
 ******************************************************************************/

package com.ibm.mq.samples.jms;

import javax.jms.Destination;
import javax.jms.JMSConsumer;
import javax.jms.JMSContext;
import javax.jms.JMSException;
import javax.jms.JMSProducer;
import javax.jms.TextMessage;

import com.ibm.msg.client.jms.JmsConnectionFactory;
import com.ibm.msg.client.jms.JmsFactoryFactory;
import com.ibm.msg.client.wmq.WMQConstants;


/**
 * A minimal and simple application for Point-to-point messaging.
 *
 * Application makes use of fixed literals, any customisations will require
 * re-compilation of this source file. Application assumes that the named queue
 * is empty prior to a run.
 *
 * Notes:
 *
 * API type: JMS API (v2.0, simplified domain)
 *
 * Messaging domain: Point-to-point
 *
 * Provider type: IBM MQ
 *
 * Connection mode: Client connection
 *
 * JNDI in use: No
 *
 */
public class JmsPutGet {

    // System exit status value (assume unset value to be 1)
    private static int status = 1;

    // Create variables for the connection to MQ
    private static String HOST = null; // Host name or IP address of your MQ instance.
    private static int PORT = 15443; // Listener port for your queue manager
    private static String CHANNEL = "SYSTEM.TLS.SVRCONN"; // Channel name
    private static String QMGR = "OM_QMGR"; // Queue manager name
    private static String QUEUE = null; // Queue that the application uses to put and get messages to and from
    private static String CIPHER = "SSL_ECDHE_RSA_WITH_AES_128_GCM_SHA256";
    private static long RETRY_INTERVAL = 5000; //Retry interval for send message retries, in milli-seconds
    private static int RETRY_NUM = -1; //Number of max retries. -1 means infinite retries

    /**
     * Main method
     *
     * @param args
     */
    public static void main(String[] args) throws Exception{
    	setProperties(args);
    	System.out.println("Connecting to: HOST: "+HOST+
			"\nPORT: "+PORT+
			"\nCHANNEL: "+CHANNEL+
			"\nQMGR: "+QMGR+
			"\nQUEUE: "+QUEUE+
			"\nCIPHER: "+CIPHER);
    	
        // Variables
        JMSContext context = null;
        Destination destination = null;
        JMSProducer producer = null;
        JMSConsumer consumer = null;
        TextMessage message = null;
        long uniqueNumber = System.currentTimeMillis() % 1000;

        try {
            // Create a connection factory
            JmsFactoryFactory ff = JmsFactoryFactory.getInstance(WMQConstants.WMQ_PROVIDER);
            JmsConnectionFactory cf = ff.createConnectionFactory();

            // Set the properties
            cf.setStringProperty(WMQConstants.WMQ_HOST_NAME, HOST);
            cf.setIntProperty(WMQConstants.WMQ_PORT, PORT);
            cf.setStringProperty(WMQConstants.WMQ_CHANNEL, CHANNEL);
            cf.setIntProperty(WMQConstants.WMQ_CONNECTION_MODE, WMQConstants.WMQ_CM_CLIENT);
            cf.setStringProperty(WMQConstants.WMQ_QUEUE_MANAGER, QMGR);
            cf.setStringProperty(WMQConstants.WMQ_SSL_CIPHER_SUITE, CIPHER);
            cf.setBooleanProperty(WMQConstants.USER_AUTHENTICATION_MQCSP, false);
            
    		System.out.println("Creating initial context and connection ...");
            
            // Sample implementation to send message with retry logic
            int counter=0;
	        while(true) {
            	try {
                    // Create JMS objects
                    context = cf.createContext();
		            destination = context.createQueue("queue:///" + QUEUE);
		            message = context.createTextMessage("Your lucky number today is " + uniqueNumber);
		            producer = context.createProducer();
		    		//if(counter==0) {
			        //    System.out.println("Connection created. Waiting for some time first time before sending message ...");
		    		//	Thread.sleep(30000);
		    		//}
            		producer.send(destination, message);
            		break;
            	} catch (Exception e) {
            		try{
            			context.close();
            		} catch(Exception ce) {
            			
            		}
                    //By default, it does an infinite number of retries until sending message succeeds
                    //If you want fixed number of retries, set the System property MQJC_RETRY_NUM to the upper limit of retries
                    //For e.g., if you want upto 120 retries (10 minutes), set MQJC_RETRY_NUM=120
                    if(counter++ == RETRY_NUM) {
                    	System.out.println("No more retries left because default unlimited retries has been overridden by user to max "+RETRY_NUM+" retries");
                    	throw e;
                    }
            		System.out.println(counter+". Error while sending message. Retrying in "+RETRY_INTERVAL+"ms ...");
            		//If message could not be sent and there is exception, retry after 5 second i.e. 5000ms
            		//To change the retry interval time, set the System property MQJC_RETRY_INTERVAL in milli-seconds
            		//For e.g., to change interval time from default 5s to 10s, set MQJC_RETRY_INTERVAL=10000
                    Thread.sleep(RETRY_INTERVAL);
                }
            } 
        	System.out.println("Sent message:\n" + message);

            consumer = context.createConsumer(destination); // autoclosable
            String receivedMessage = consumer.receiveBody(String.class, 15000); // in ms or 15 seconds

            System.out.println("\nReceived message:\n" + receivedMessage);
            
            recordSuccess();
        } catch (Exception ex) {
            recordFailure(ex);
        }

        System.exit(status);
    } // end main()

    /**
     * Record this run as successful.
     */
    private static void recordSuccess() {
        System.out.println("SUCCESS");
        status = 0;
        return;
    }

    /**
     * Record this run as failure.
     *
     * @param ex
     */
    private static void recordFailure(Exception ex) {
        if (ex != null) {
            if (ex instanceof JMSException) {
                processJMSException((JMSException) ex);
            } else {
                System.out.println(ex);
            }
        }
        System.out.println("FAILURE");
        status = -1;
        return;
    }

    /**
     * Process a JMSException and any associated inner exceptions.
     *
     * @param jmsex
     */
    private static void processJMSException(JMSException jmsex) {
        System.out.println(jmsex);
        Throwable innerException = jmsex.getLinkedException();
        if (innerException != null) {
            System.out.println("Inner exception(s):");
        }
        while (innerException != null) {
            System.out.println(innerException);
            innerException = innerException.getCause();
        }
        return;
    }
    
    private static void setProperties(String[] args) {
    	if(System.getProperty("MQJC_HOST")!=null)
    		HOST = System.getProperty("MQJC_HOST");
    	if(System.getProperty("MQJC_PORT")!=null)
    		PORT = Integer.parseInt(System.getProperty("MQJC_PORT"));
    	if(System.getProperty("MQJC_CHANNEL")!=null)
    		CHANNEL = System.getProperty("MQJC_CHANNEL");
    	if(System.getProperty("MQJC_QMGR")!=null)
    		QMGR = System.getProperty("MQJC_QMGR");
    	if(System.getProperty("MQJC_QUEUE")!=null)
    		QUEUE = System.getProperty("MQJC_QUEUE");
    	if(System.getProperty("MQJC_CIPHER")!=null)
    		CIPHER = System.getProperty("MQJC_CIPHER");
    	if(System.getProperty("MQJC_RETRY_INTERVAL")!=null)
    		RETRY_INTERVAL = Long.parseLong(System.getProperty("MQJC_RETRY_INTERVAL"));
    	if(System.getProperty("MQJC_RETRY_NUM")!=null)
    		RETRY_NUM = Integer.parseInt(System.getProperty("MQJC_RETRY_NUM"));
    	
    	if(HOST==null) {
    		System.out.println("HOST cannot be null. Pass -DMQJC_HOST=<host name/ip>");
    		System.exit(1);
    	}
    	if(QUEUE==null) {
    		System.out.println("QUEUE cannot be null. Pass -DMQJC_QUEUE=<queue name>");
    		System.exit(1);
    	}
    }
}
