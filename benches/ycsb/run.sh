#!/usr/bin/env bash

set -eu
set -o pipefail

source ../common.sh

YCSB_TYPES="${YCSB_TYPES:-all}"
YCSB_RECORDCOUNT="${YCSB_RECORDCOUNT:-1000000}"
YCSB_OPERATIONCOUNT="${YCSB_OPERATIONCOUNT:-1000000}"
YCSB_MEMTXMEMORY="${YCSB_MEMTXMEMORY:-2000000000}"
YCSB_RUNS="${YCSB_RUNS:-1}"
YCSB_WORKLOADS="${YCSB_WORKLOADS:-all}"

TAR_VER=$(get_tarantool_version)

function run_ycsb {
	local mode="$1"
	local srvlua="tarantool/src/main/conf/tarantool-${mode}.lua"
	sed "s/listen=.*/listen=3301,\n   memtx_memory = $YCSB_MEMTXMEMORY,/" -i "$srvlua"
	sed 's/logger_nonblock.*//' -i "$srvlua"
	sed 's/logger/log/' -i "$srvlua"
	sed 's/read,write,execute/create,read,write,execute/' -i "$srvlua"
	maybe_under_numactl "${numaopts[@]}" -- \
		"$TARANTOOL_EXECUTABLE" "$srvlua" 2>&1 &
	wait_for_tarantool_runnning 3301 10

	local workloads=(a b c d e f)

	if [ -n "$YCSB_WORKLOADS" -a "$YCSB_WORKLOADS" != "all" ]; then
		IPS=, read -ra workloads <<< "$YCSB_WORKLOADS"
	fi

	for l in "${workloads[@]}"; do
		echo "=============== $l"
		for r in $( seq 1 "$YCSB_RUNS" ); do
			local res="$plogs/run${l}_${r}"
			echo "---------------- ${l}: $r"
			echo "tarantool.port=3301" >> "workloads/workload${l}"
			maybe_under_numactl "${numaopts[@]}" -- \
				./bin/ycsb load tarantool -s -P "workloads/workload${l}" > "${res}.load" 2>&1 || cat "${res}.load"
			sync_disk
			maybe_drop_cache

			maybe_under_numactl "${numaopts[@]}" -- \
				./bin/ycsb run tarantool -s -P "workloads/workload${l}" > "${res}.log" 2>&1 || cat "${res}.log"

			grep Thro "${res}.log" | awk '{ print "Overall result: "$3 }' | tee "${res}.txt"
			sed "s#Overall result#$l $r#g" "${res}.txt" >> "${plogs}/ycsb.${mode}_result.txt"

			stop_and_clean_tarantool
		done
	done
}

types=(hash tree)

if [ -n "$YCSB_TYPES" -a "$YCSB_TYPES" != 'all' ]; then
	IPS=, read -ra types <<< "$YCSB_TYPES"
fi

numaopts=(--membind=1 --cpunodebind=1 '--physcpubind=6,7,8,9,10,11')

for f in workloads/workload[a-f] ; do
	sed "s#recordcount=.*#recordcount=$YCSB_RECORDCOUNT#g" -i "$f"
	sed "s#operationcount=.*#operationcount=$YCSB_OPERATIONCOUNT#g" -i "$f"
	echo "tarantool.port=3301" >> "$f"
done


plogs=results
rm -rf "$plogs"
mkdir "$plogs"

for t in "${types[@]}"; do
	run_ycsb "$t"
done

echo "${TAR_VER}" | tee "ycsb.${mode}_t_version.txt"
cp -f "${plogs}/ycsb.${mode}_result.txt" .

echo "Tarantool TAG:"
cat "ycsb.${mode}_t_version.txt"
echo "Overall results:"
echo "================"
cat "ycsb.${mode}_result.txt"
