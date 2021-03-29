#!/bin/bash
# -*- mode: sh -*-
#
# Copyright DataStax, Inc, 2017
#   Please review the included LICENSE file for more information.
#

set -e

. /base-checks.sh

link_external_config "${DSE_HOME}"

#create directories for holding the node's data, logs, etc.
: ${CREATE_HOLDING_DIRS='no'}

if [[ ${CREATE_HOLDING_DIRS} == "yes" ]]; then
  mkdir -p /var/lib/spark/worker
  mkdir -p /var/lib/spark/rdd
  mkdir -p /var/log/spark/worker
  mkdir -p /var/log/spark/master
fi;

############################################
# Set up variables/configure the image
############################################

IP_ADDRESS="$(hostname --ip-address)"
CASSANDRA_CONFIG="${DSE_HOME}/resources/cassandra/conf/cassandra.yaml"
CASSANDRA_RACK_CONFIG="${DSE_HOME}/resources/cassandra/conf/cassandra-rackdc.properties"

cp -r ${DSE_HOME}/resources/dse/conf-template/* ${DSE_HOME}/resources/dse/conf
cp -r ${DSE_HOME}/resources/cassandra/conf-template/* ${DSE_HOME}/resources/cassandra/conf
cp -r ${DSE_HOME}/resources/spark/conf-template/* ${DSE_HOME}/resources/spark/conf

ls -la ${DSE_HOME}/resources/cassandra/conf
# SNITCH sets the snitch this node will use. Use GossipingPropertyFileSnitch if not set
: ${SNITCH=GossipingPropertyFileSnitch}

# NATIVE_TRANSPORT_ADDRESS is where we listen for drivers/clients to connect to us. Setting to 0.0.0.0 by default is fine
# since we'll be specifying the NATIVE_TRANSPORT_BROADCAST_ADDRESS below
: ${NATIVE_TRANSPORT_ADDRESS='0.0.0.0'}

# LISTEN_ADDRESS is where we listen for other nodes who want to communicate. 'auto' is not a valid value here,
# so use the hostname's IP by default
: ${LISTEN_ADDRESS='auto'}
if [ "$LISTEN_ADDRESS" = 'auto' ]; then
    LISTEN_ADDRESS="$IP_ADDRESS"
fi

# BROADCAST_ADDRESS is where we tell other nodes to communicate with us. Again, 'auto' is not a valid value here,
# so default to the LISTEN_ADDRESS or the hostname's IP address if set to 'auto'
: ${BROADCAST_ADDRESS="$LISTEN_ADDRESS"}
if [ "$BROADCAST_ADDRESS" = 'auto' ]; then
    BROADCAST_ADDRESS="$IP_ADDRESS"
fi

# By default, tell drivers/clients to use the same address that other nodes are using to communicate with us
: ${NATIVE_TRANSPORT_BROADCAST_ADDRESS=$BROADCAST_ADDRESS}

# SEEDS is for other nodes in the cluster we know about. If not set (because we're the only node maybe), just
# default to ourself
: ${SEEDS:="$BROADCAST_ADDRESS"}

# modify cassandra.yaml only if not linked externally
if should_auto_configure "$CASSANDRA_CONFIG" ; then
    echo "Applying changes to $CASSANDRA_CONFIG ..."

    sed -ri 's/(endpoint_snitch:).*/\1 '"$SNITCH"'/' "$CASSANDRA_CONFIG"

    # Replace the default seeds setting in cassandra.yaml
    sed -ri 's/(- seeds:).*/\1 "'"$SEEDS"'"/' "$CASSANDRA_CONFIG"

    # Update the following settings in the cassandra.yaml file based on the ENV variable values
    for name in \
        broadcast_address \
        native_transport_broadcast_address \
        cluster_name \
        listen_address \
        num_tokens \
        native_transport_address \
        start_native_transport \
        ; do
        var="${name^^}"
        val="${!var}"
        if [ "$val" ]; then
          sed -ri 's/^(# )?('"$name"':).*/\2 '"$val"'/' "$CASSANDRA_CONFIG"
        fi
    done
    echo "done."
fi

if should_auto_configure "$CASSANDRA_RACK_CONFIG" ; then
    echo "Applying changes to $CASSANDRA_RACK_CONFIG ..."
    for rackdc in dc rack; do
        var="${rackdc^^}"
        val="${!var}"
        if [ "$val" ]; then
            sed -ri 's/^('"$rackdc"'=).*/\1 '"$val"'/' "$CASSANDRA_RACK_CONFIG"
        fi
    done
    echo "done."
fi

if [ ! -z "$OPSCENTER_IP" ]; then
    echo "Configuring agent to connect to OpsCenter (${OPSCENTER_IP}) "
    cat > "$DSE_AGENT_HOME/conf/address.yaml" <<EOF
stomp_interface: ${OPSCENTER_IP}
use_ssl: 0
local_interface: ${IP_ADDRESS}
hosts: ["${IP_ADDRESS}"]
cassandra_install_location: $DSE_HOME
cassandra_log_location: /var/log/cassandra
EOF

$DSE_AGENT_HOME/bin/datastax-agent

fi

# Run the command
if [ "$USE_MGMT_API" = "true" ] && [ -d "$DSE_HOME/resources/management-api" ] ; then
    echo "Starting Management API"

    MGMT_API_ARGS=""

    # Hardcoding these for now
    DSE_MGMT_DSE_SOCKET="--dse-socket /tmp/dse.sock"
    DSE_MGMT_LISTEN_TCP="--host tcp://0.0.0.0:8080"
    DSE_MGMT_LISTEN_SOCKET="--host file:///tmp/dse-mgmt.sock"

    MGMT_API_ARGS="$MGMT_API_ARGS $DSE_MGMT_DSE_SOCKET $DSE_MGMT_LISTEN_TCP $DSE_MGMT_LISTEN_SOCKET"

    # These will generally come from the dse-operator
    if [ ! -z "$DSE_MGMT_EXPLICIT_START" ]; then
        DSE_MGMT_EXPLICIT_START="--explicit-start $DSE_MGMT_EXPLICIT_START"
        MGMT_API_ARGS="$MGMT_API_ARGS $DSE_MGMT_EXPLICIT_START"
    fi

    if [ ! -z "$DSE_MGMT_TLS_CA_CERT_FILE" ]; then
        DSE_MGMT_TLS_CA_CERT_FILE="--tlscacert $DSE_MGMT_TLS_CA_CERT_FILE"
        MGMT_API_ARGS="$MGMT_API_ARGS $DSE_MGMT_TLS_CA_CERT_FILE"
    fi
    if [ ! -z "$DSE_MGMT_TLS_CERT_FILE" ]; then
        DSE_MGMT_TLS_CERT_FILE="--tlscert $DSE_MGMT_TLS_CERT_FILE"
        MGMT_API_ARGS="$MGMT_API_ARGS $DSE_MGMT_TLS_CERT_FILE"
    fi
    if [ ! -z "$DSE_MGMT_TLS_KEY_FILE" ]; then
        DSE_MGMT_TLS_KEY_FILE="--tlskey $DSE_MGMT_TLS_KEY_FILE"
        MGMT_API_ARGS="$MGMT_API_ARGS $DSE_MGMT_TLS_KEY_FILE"
    fi

    if [ ! -z "$DSE_MGMT_PID_FILE" ]; then
        DSE_MGMT_PID_FILE="--pidfile $DSE_MGMT_PID_FILE"
        MGMT_API_ARGS="$MGMT_API_ARGS $DSE_MGMT_PID_FILE"
    fi

    if [ ! -z "$DSE_MGMT_DSE_PATH" ]; then
        DSE_MGMT_DSE_PATH="--dse-exec $DSE_MGMT_DSE_PATH"
        MGMT_API_ARGS="$MGMT_API_ARGS $DSE_MGMT_DSE_PATH"
    fi

    if [ ! -z "$DSE_MGMT_NO_KEEP_ALIVE" ]; then
        DSE_MGMT_NO_KEEP_ALIVE="--no-keep-alive $DSE_MGMT_NO_KEEP_ALIVE"
        MGMT_API_ARGS="$MGMT_API_ARGS $DSE_MGMT_NO_KEEP_ALIVE"
    fi

    MGMT_API_JAR="$(find "${DSE_HOME}/resources/management-api" -name *.jar)"

    echo "Running" java -Xms128m -Xmx128m -jar "$MGMT_API_JAR" $MGMT_API_ARGS
    exec java -Xms128m -Xmx128m -jar "$MGMT_API_JAR" $MGMT_API_ARGS
else
    echo "Running $@"
    exec "$@"
fi
