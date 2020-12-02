#!/usr/bin/env bash

set -eu
set -o pipefail

source ../common.sh

LINKBENCH_REQUESTS="${LINKBENCH_REQUESTS:-2000000}"
LINKBENCH_REQUESTERS="${LINKBENCH_REQUESTERS:-1}"
LINKBENCH_WORKLOAD_SIZE="${LINKBENCH_WORKLOAD_SIZE:-5000000}"

TAR_VER=$(get_tarantool_version)
numaopts=(--membind=1 --cpunodebind=1 '--physcpubind=6,7,8,9,10,11')

mvn clean package -Dmaven.test.skip=true
make -C src/tarantool -B

tfile=src/tarantool/app.lua

stop_and_clean_tarantool
maybe_under_numactl "${numaopts[@]}" -- tarantool "$tfile" 1>/dev/null 2>/dev/null &

cfgfile=config/LinkConfigTarantool.properties
sed "s/^maxid1 = .*/maxid1 = $LINKBENCH_WORKLOAD_SIZE/g" -i config/FBWorkload.properties
sed "s/^requesters = .*/requesters = $LINKBENCH_REQUESTERS/g" -i "$cfgfile"
sed "s/^requests = .*/requests = $LINKBENCH_REQUESTS/g" -i "$cfgfile"

maybe_under_numactl "${numaopts[@]}" -- \
	./bin/linkbench -c "$cfgfile" -l 2>&1 | tee loading.res.txt

sync_disk
maybe_drop_cache

maybe_under_numactl "${numaopts[@]}" -- \
	./bin/linkbench -c "$cfgfile" -r 2>&1 | tee linkbench_output.txt

kill_tarantool

grep "REQUEST PHASE COMPLETED" linkbench_output.txt | sed "s/.*second = /linkbench:/" | tee -a linkbench.ssd_result.txt
echo "${TAR_VER}" | tee linkbench.ssd_t_version.txt

echo "Tarantool TAG:"
cat linkbench.ssd_t_version.txt
echo "Overall results:"
echo "================"
cat linkbench.ssd_result.txt
