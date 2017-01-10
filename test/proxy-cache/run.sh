#!/bin/bash

set -x

PID=

function run {
	echo "== Run ${LOOP}"
	echo ${PIDFILE}
	rm -f ${PIDFILE}
	setsid ${LOOP} ${PIDFILE} < /dev/null &> /dev/null &
	for i in `seq 100`; do
		test -f ${PIDFILE} && break
		sleep 1
	done
	PID=`cat ${PIDFILE}`
	echo ${PID}
}

function prepare {
	${CRIU} image-cache -d -vvvv -o ${LOG}/image-cache.log \
						--port ${PROXY_CACHE_TCP_PORT} --images-dir $1
	sleep 1

	${CRIU} image-proxy -d -vvvv -o ${LOG}/image-proxy.log \
						--address localhost \
						--port ${PROXY_CACHE_TCP_PORT} --images-dir $1
	sleep 1
}

function predump {
	echo "== Predump ${PID}"
	${CRIU} pre-dump -vvvv --tree ${PID} --images-dir ${PREDIR} \
					 -o ${LOG}/predump.log \
					 --remote
	return $?
}

function dump {
	echo "== Dump ${PID}"
	${CRIU} dump -vvvv --tree ${PID} --images-dir ${DUMPDIR} \
			-o ${LOG}/dump.log --prev-images-dir ${PREDIR} --track-mem \
			--remote
	return $?
}

function restore {
	echo "== Restore ${DUMPDIR}"
	${CRIU} restore -vvvv --images-dir ${DUMPDIR} --restore-detached \
			-o ${LOG}/restore.log \
			--remote
	return $?
}

function result {
	local BGRED='\033[41m'
	local BGGREEN='\033[42m'
	local NORMAL=$(tput sgr0)

	if [ $1 -ne 0 ]; then
		echo -e "${BGRED}FAIL${NORMAL}"
		exit 1
	else
		echo -e "${BGGREEN}PASS${NORMAL}"
	fi
}

function test_dump_restore {
	echo "==== Check if dump-restore works with proxy-cache"

	run
	test -d ${DUMPDIR} && rm -rf ${DUMPDIR}
	mkdir -p ${DUMPDIR}
	prepare ${DUMPDIR}
	dump; result $(($?))
	restore ; result $(($?))

	kill -SIGKILL ${PID}
	pkill criu
}

function test_predump_dump_restore {
	echo "==== Check if predump-dump-restore works with proxy-cache"
	run
	test -d ${PREDIR} && rm -rf ${PREDIR}
	mkdir -p ${PREDIR}
	prepare ${PREDIR}
	predump; result $(($?))
	test -d ${DUMPDIR} && rm -rf ${DUMPDIR}
	mkdir -p ${DUMPDIR}
	ln -s ${PREDIR}"/img-proxy.sock" ${DUMPDIR}"/img-proxy.sock"
	ln -s ${PREDIR}"/img-cache.sock" ${DUMPDIR}"/img-cache.sock"
	dump; result $(($?))
	restore ; result $(($?))

	kill -SIGKILL ${PID}
	pkill criu
}

test_dump_restore
test_predump_dump_restore
