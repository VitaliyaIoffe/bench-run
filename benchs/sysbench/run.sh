#!/usr/bin/env bash

set -eu
set -o pipefail

runs=1

TAR_VER=$(tarantool -v | grep -e "Tarantool" |  grep -oP '\s\K\S*')
numaconf="numactl --membind=1 --cpunodebind=1 --physcpubind=6,7,8,9,10,11"

ARRAY_TESTS=(
    "oltp_read_only"
#    "oltp_write_only"
#    "oltp_read_write"
#    "oltp_update_index"
#    "oltp_update_non_index"
#    "oltp_insert"
#    "oltp_delete"
#    "oltp_point_select"
#    "select_random_points"
#    "select_random_ranges"
#    "bulk_insert"
)

WARMUP_TIME=5
TIME=20
DBMS="tarantool"
THREADS=200
opts="--db-driver=${DBMS} --threads=${THREADS}"

export LD_LIBRARY_PATH=/usr/local/lib

for test in "${ARRAY_TESTS[@]}"; do
    res=0
    tlog=sysbench_${test}_results.txt
    rm -f $tlog
    maxres=0
    for run in `eval echo {1..$runs}` ; do
        echo "------------ $test ------------ rerun: # $run ------------"
        `dirname $0`/run_tnt.sh >tnt_server.txt 2>&1 || ( cat tnt_server.txt ; exit 1 )

        sysbench $test $opts cleanup >sysbench_output.txt
        sysbench $test $opts prepare >>sysbench_output.txt
 
        $numaconf sysbench $test $opts \
            --time=${TIME} --warmup-time=${WARMUP_TIME} run >>sysbench_output.txt

        $numaconf sysbench $test $opts cleanup >>sysbench_output.txt

        cat sysbench_output.txt | grep -e 'transactions:' | grep -oP '\(\K\S*' | tee $tlog
        tres=`cat $tlog | sed 's#^.*:##g' | sed 's#\..*$##g'`
        res=$(($res+$tres))
        if [[ $tres -gt $maxres ]]; then maxres=$tres ; fi
    done
    res=$(($res/$runs))
    echo "${test}: $res" >>Sysbench_result.txt

    echo "Subtest '$test' results:"
    echo "==============================="
    echo "Average result: $res"
    echo "Maximum result: $maxres"
    printf "Deviations (AVG -> MAX): %.2f" `bc <<< "scale = 4; (1 - $res / $maxres) * 100"` ; echo %
done

echo ${TAR_VER} | tee Sysbench_t_version.txt

echo "Tarantool TAG:"
cat Sysbench_t_version.txt
echo "Overall results:"
echo "================"
cat Sysbench_result.txt
echo " "
echo "Publish data to bench database"
/opt/bench-run/benchs/publication/publish.py
