#!/bin/bash

if [ $# -lt 3 ]; then
    echo "Usage: client_start.sh {init | test}  <ip_address> <postgresql_inst_number> <keep_alive> <pipe_num>"
    exit 0
fi

BASE_DIR=$(cd ~; pwd)

REDIS_TEST_DIR=${BASE_DIR}/apptests/postgresql/
REDIS_CMD_DIR=/usr/local/postgresql/bin
#######################################################################################
# Notes:
#  To start client tests
#  Usage: client_start.sh {init | test} <ip_addr> <start_cpu_num> <postgresql_inst> <keep-alive> <pipe_num>
#######################################################################################

ip_addr=${2}
base_port_num=7000
start_cpu_num=${3}
postgresql_inst_num=${4}
keep_alive=${5}
pipeline=${6}

data_num=10000000
data_size=10
key_space_len=10000

if [[ ${pipeline} -eq 100 ]] ; then
    echo "Change num_of_req to 100000000"
    data_num=100000000
fi
    
if [ "$1" == "init" ] ; then
    #Step 1: Prepare data
    mkdir -p ${REDIS_TEST_DIR}
    pushd ${REDIS_TEST_DIR} > /dev/null

    echo 1 > /proc/sys/net/ipv4/tcp_timestamps
    echo 1 > /proc/sys/net/ipv4/tcp_tw_reuse
    echo 1 > /proc/sys/net/ipv4/tcp_tw_recycle
    echo 2048 65000 > /proc/sys/net/ipv4/ip_local_port_range
    echo 2621440 > /proc/sys/net/core/somaxconn
    echo 2621440 > /proc/sys/net/core/netdev_max_backlog
    echo 2621440 > /proc/sys/net/ipv4/tcp_max_syn_backlog
    echo 1 > /proc/sys/net/netfilter/nf_conntrack_tcp_timeout_time_wait
    echo 2621440 > /proc/sys/net/netfilter/nf_conntrack_max
    ulimit -n 1024000
    #data_num=10000
    #data_size=128

    python ${APP_ROOT}/apps/postgresql/postgresql_test1/scripts/generate_inputdata.py ./input_data ${data_num} ${data_size}
   
    let "postgresql_inst_num--"
    for index in $(seq 0 ${postgresql_inst_num})
    do
        echo "call postgresql-cli to initialize data for postgresql-${index}"
        port=`expr ${base_port_num} + ${index} + ${start_cpu_num}`
        echo "flushdb"  |  ${REDIS_CMD_DIR}/postgresql-cli -h ${ip_addr} -p ${port} --pipe
        cat ./input_data | ${REDIS_CMD_DIR}/postgresql-cli -h ${ip_addr} -p ${port} --pipe
    done

    popd > /dev/null

elif [ "$1" == "test" ] ; then
    pushd ${REDIS_TEST_DIR} > /dev/null
    rm postgresql_benchmark_log*

    let "postgresql_inst_num--"
    for index in $(seq 0 ${postgresql_inst_num})
    do
        port=`expr ${base_port_num} + ${index} + ${start_cpu_num}`
        taskindex=`expr 17 + ${index}`
        #taskend=`expr 6 + ${taskindex}`
        echo "call postgresql-benchmark to test postgresql-${index}"

        taskset -c ${taskindex} ${REDIS_CMD_DIR}/postgresql-benchmark -h ${ip_addr} -p ${port} -c 50 -n ${data_num} -d ${data_size} -k ${keep_alive} -r ${key_space_len} -P ${pipeline} -t get > postgresql_benchmark_log_${port} & 
        #${REDIS_CMD_DIR}/postgresql-benchmark -h ${ip_addr} -p ${port} -c 50 -n ${data_num} -d ${data_size} -k ${keep_alive} -r ${key_space_len} -P ${pipeline} -t get > postgresql_benchmark_log_${port} &
    done

    echo "Please check results under ${REDIS_TEST_DIR} directory"
    echo "You could use scripts/analysis_qps_lat.py to get qps and latency from logs"

    popd > /dev/null
else 
    echo "parameter should be {init | test} "
fi

echo "**********************************************************************************"
