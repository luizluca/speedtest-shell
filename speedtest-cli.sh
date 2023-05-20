#!/bin/sh
#
# Speedtest.net ookla shell client
#

next_free_fd() {           
	local fd=3 max=$(ulimit -n)
	while ((++fd < max)); do
	   ! true <&"$fd" && break
	done 2>&-              
	eval $1=$fd
}

err(){	printf "%s\n" "$1" >&2; }

die(){
	local errcode=$1; shift
	[ "$LOGLEVEL" -lt "$ERR" ] || err "$@"
	exit $errcode
} 

awkcalc() {
	local exp="$1"; shift
	echo "$@" | LC_NUMERIC=C awk '{ print '"$exp"' }'
}

time_in_ms_uptime() {
	local cmd_fd="${1:?Send channel FD is missing}"
	local send_cmd="${2:?Send command missing}"
	local recv_cmd="${3:?Recv command missing}"
	local check_cmd="${4:-true}"
	local errcode
	local t1 t2 x
	read t1 x < /proc/uptime ||
		{ errcode=$?; [ "$LOGLEVEL" -lt "$WARN" ] || err "Failed on reading tick"; return $errcode; }
	{ $send_cmd; } >&${cmd_fd} </dev/null ||
		{ errcode=$?; [ "$LOGLEVEL" -lt "$WARN" ] || err "Failed on send cmd '$send_cmd'"; return $errcode; }
	{ $recv_cmd; } &>/dev/null ||
		{ errcode=$?; [ "$LOGLEVEL" -lt "$WARN" ] || err "Failed on recv cmd '$recv_cmd'"; return $errcode; }
	read t2 x < /proc/uptime
	eval "$check_cmd" || return 1
	t1=$(echo "$t1" | tr -d '.,')
	t2=$(echo "$t2" | tr -d '.,')
	echo "$((t2-t1))0"
}

time_in_ms_hrtimer(){
	local cmd_fd="${1:?Send channel FD is missing}"
	local send_cmd="${2:?Send command missing}"
	local recv_cmd="${3:?Recv command missing}"
	local check_cmd="${4:-true}"
	local errcode
	local t1 t2 x
	{ read -r _; read -r _; read -r now at t1 _; } < /proc/timer_list ||
		{ errcode=$?; [ "$LOGLEVEL" -lt $WARN ] || err "Failed on reading tick"; return $errcode; }
	{ $send_cmd; } >&${cmd_fd} </dev/null ||
		{ errcode=$?; [ "$LOGLEVEL" -lt $WARN ] || err "Failed on send cmd '$send_cmd'"; return $errcode; }
	{ $recv_cmd; } &>/dev/null ||
		{ errcode=$?; [ "$LOGLEVEL" -lt $WARN ] || err "Failed on recv cmd '$recv_cmd'"; return $errcode; }
	{ read -r _; read -r _; read -r now at t2 _ ; } < /proc/timer_list
	eval "$check_cmd" || return 1
	t1=$(echo "$t1" | tr -d '.,')
	t2=$(echo "$t2" | tr -d '.,')
	echo "$(( (t2-t1) / 1000000 ))"
}

time_in_ms_epochtime() {
	local cmd_fd="${1:?Send channel FD is missing}"
	local send_cmd="${2:?Send command missing}"
	local recv_cmd="${3:?Recv command missing}"
	local check_cmd="${4:-true}"
	local t1 t2
	t1=${EPOCHREALTIME}
	{ $send_cmd; } >&${cmd_fd} </dev/null ||
		{ errcode=$?; [ "$LOGLEVEL" -lt $WARN ] || err "Failed on send cmd '$send_cmd'"; return $errcode; }
	{ $recv_cmd; } &>/dev/null ||
		{ errcode=$?; [ "$LOGLEVEL" -lt $WARN ] || err "Failed on recv cmd '$recv_cmd'"; return $errcode; }
	t2=${EPOCHREALTIME}
	t1=$(echo "$t1" | tr -d '.,')
	t2=$(echo "$t2" | tr -d '.,')
	echo "$(( (t2-t1) / 1000 ))"
}

monitor_cpu(){
	local tag
	local last_idle=0
	while true; do
		tag=""
		while read -r line; do
			tag=${line%% *}
			[ "$tag" = cpu ] || continue
			line=${line#* }
			line=${line#* }
			line=${line#* }
			line=${line#* }
			line=${line#* }
			idle=${line%% *}
			if [ "$idle" = "$last_idle" ]; then
				[ "$LOGLEVEL" -lt $WARN ] || err "CPU is struggling... expect worse measures"
				# stop as we have already warned
				break 2
			fi
			#err "CPU: $last_idle $idle : delta $((idle-last_idle))s"
			last_idle=${idle}
			break
		done < /proc/stat
		sleep 1
	done
}

PROTOS="6 4"
DOWNLOAD_SIZE=$((50 * 1024 * 1024))
UPLOAD_SIZE=$((20 * 1024 * 1024))
PING_REPEAT=10
PRINTF_MAX_REPEAT=$(((1<<31)-1))
SPEEDTEST_SERVERS=https://www.speedtest.net/speedtest-servers-static.php
PORT=8080
SERVER=""
LOGLEVEL=2
NONE=0 ERR=1 WARN=2 INFO=3 TRACE=4
LIST_ONLY=false
NETCATS="socat netcat nc"
BIND=""

help(){
	cat <<EOF
Usage ${0##*/} [-v] [-V] [ -4 | -6 ] [ -c ( nc | netcat | socat ) ] [ -d bytes ]
      [ -i times ] [-I device] [ -p port ] [ -s server] [ -u bytes ]

Runs a speedtest 

Options:
 -4	Connect only to IPv4 servers. Default is IPv6 or IPv4.
 -6	Connect only to IPv6 servers Default is IPv6 or IPv4.
 -c	Define the netcat client. By default, it tries, socat, netcat and nc
 -d	Define the download payload size in bytes. Default is $DOWNLOAD_SIZE
 -i	Define number of times a PING command is issued. Default is $PING_REPEAT
 -I     Bind to interface (only works with socat)
 -l     List close servers
 -s	Define the server address (name or ip address) with port. IPv6 addresses
	needs to use braces, like in URL. Default is to look for the fastest server.
 -u	Define the upload payload size in bytes; Default is $UPLOAD_SIZE
 -v	More verbose (can be repeated)
 -V	Less verbose (can be repeated)

If not server was provided, it will look for the best one at:
 $SPEEDTEST_SERVERS

EOF
}

while getopts '46c:d:hi:I:ls:u:vV' opt; do
	case "$opt" in
		4) PROTOS=4;;
		6) PROTOS=6;;
		c) NETCATS="$OPTARG";;
		d) DOWNLOAD_SIZE=$OPTARG;;
		h) help; exit;;
		i) PING_REPEAT=$OPTARG;;
		I) BIND=$OPTARG;;
		l) LIST_ONLY=true;;
		s) SERVER=$OPTARG ;;
		u) UPLOAD_SIZE=$OPTARG;;
		v) LOGLEVEL=$((LOGLEVEL+1));;
		V) LOGLEVEL=$((LOGLEVEL-1));;
		*) help; exit 1;;
	esac
done

for cmd in $NETCATS; do
	command -v $cmd 2>/dev/null >/dev/null || continue
	[ "$LOGLEVEL" -lt $INFO ] || err "Using '$cmd' as client"
	case $cmd in
		socat)
			nc_socat(){
				socat_args=''
				[ "$LOGLEVEL" -ge $INFO ] || socat_verbose="$socat_args -lf /dev/null"
				[ "$LOGLEVEL" -lt $TRACE ] || socat_verbose="$socat_args -v"
				if [[ "$1" = *:* ]]; then
					socat $socat_verbose - "tcp6-connect:[$1]:$2${BIND:+,so-bindtodevice=$BIND}"
				else
					socat $socat_verbose - "tcp-connect:$1:$2${BIND:+,so-bindtodevice=$BIND}"
				fi
			}
			NETCAT=nc_socat
		;;
		*)
			NETCAT="$cmd"
		;;
	esac
	break
done

if ! command -v getent 2>/dev/null >/dev/null; then
	[ "$LOGLEVEL" -lt $WARN ] || err "getent not found. Using ping instead."
	getent() {
		local protos="-4 -6"
		case "$1" in
			ahostsv4) protos=-4;;
			ahostsv6) protos=-6;;
			ahosts)   ;;
			hosts)    protos="-c1";;
			"")     [ "$LOGLEVEL" -lt $ERR ] || err "fake-getent: wrong number of arguments"
				return 1;;
			*)
				[ "$LOGLEVEL" -lt $ERR ] || err "fake-getent only supports ( ahosts[v4|v6] | host )"
				return 1;;
		esac
		shift
		local host
		for host; do
			local proto
			for proto in $protos; do
				local out ipaddr
				out=$(ping -n -W1 -w1 -q -c1 $proto $host 2>&1) ||
					continue
				ipaddr=$(echo "$out" | sed -r 's/^[^\(]* \(([^)]+)\).*/\1/;q')
				if [ "$proto" = -c1 ]; then
					printf "%s\n" "$ipaddr"
				else
					printf "%s %s %s\n" "$ipaddr" STREAM "$host"
					printf "%s %s\n" "$ipaddr" DGRAM
					printf "%s %s\n" "$ipaddr" RAW
				fi
			done
		done
	}
fi

[ "$NETCAT" ] ||
	die 1 "I need at least a netcat-like command (socat, nc, netcat)"

#time_in_ms_uptime 2 "sleep 0.231" "true"
#time_in_ms_hrtimer 2 "sleep 0.231" "true"
#time_in_ms_epochtime 2 "sleep 0.231" "true"

if [ -n "$EPOCHREALTIME" ]; then
	time_in_ms=time_in_ms_epochtime
elif [ -r /proc/timer_list ]; then
	time_in_ms=time_in_ms_hrtimer
elif [ -r /proc/uptime ]; then
	time_in_ms=time_in_ms_uptime
else
	die 1 "I need a source of ticks, like /proc/uptime or /proc/timer_list"
fi

set -e

HEADER_PRINTED=false
CSV_FORMAT="%s\t%s\t%s\t%s\n"
human_format() {
	awk -v unit="$2" -vvalue="$1" '
		BEGIN { 
			SI["m"]=1/1000
			SI[""]=1
			SI["k"]=1000
			SI["M"]=1000000
			SI["G"]=1000000000
			IEC[""]=1
			IEC["k"]=lshift(1,10)
			IEC["M"]=lshift(1,20)
			IEC["G"]=lshift(1,30)

			if (value < 0.5) {
				prefix="m"
				format="%d %s"
			} else if (value > lshift(1,10)) {
				format="%0.4f%s\n"
				if (value > lshift(1,30))
					prefix="G"
				else if (value > lshift(1,20))
					prefix="M"
				else
					prefix="k"
				format="%0.4f %s"
			} else {
				format="%f %s"
				prefix=""
			}

			if (unit=="seconds") {
				printf format "\n", value/SI[prefix], prefix "s"
			} else if (unit ~ /(bytes|bits)/) {
				if (unit ~ "per_second")
					suffix="/s"
				else
					suffix=""

				if (unit ~ /bytes/)
					symbol="B"
				else
					symbol="b"

				printf format " ", value/IEC[prefix], (prefix=="k"?"K":prefix) "i" symbol suffix
				printf format "\n", value/SI[prefix], prefix "" symbol suffix
			}
		}
	'
}

print_result() {
	local test="$1"
	local prop="$2"
	local unit="$3"
	local value="$4"
	case $FORMAT in
		plain)
			printf "%s\t%s\n" "${prop}" "$value";;
		prometheus)
			#download_speed_bps	Download speed (bit/s)
			#upload_speed_bps	Upload speed (bit/s)
			#ping_ms	Latency (ms)
			#bytes_received	Bytes received during test
			#bytes_sent	Bytes sent during test

			echo "speedtest_${test}_${prop}_${unit}{server="$server:$port",address="$ip_address",family="ipv$proto"} $value";;
		csv) 
			"$HEADER_PRINTED" ||
				printf "$CSV_FORMAT" "server" "test" "property" "unit" "value"
			HEADER_PRINTED=true
			printf "$CSV_FORMAT" "$@";;
		cli|*) 
			"$HEADER_PRINTED" || {
				echo "Server: $server:$port ($ip_address/ipv$proto)"
				echo "============================================"
				HEADER_PRINTED=true
			}
			echo "${test}.${prop} = $(human_format "$value" "$unit")"
	esac
}

test_server() {
	local server="$1"; shift

	if [ "$#" -eq 0 ]; then
		local test_PING=1 test_DOWNLOAD=1 test_UPLOAD=1
	else
		for param; do
			local "test_$param"=1
		done
	fi

	port=${server##*:}
	server=${server%:*}
	if [ "${server#[}" != "${server}" ]; then
		server=${server#[}
		server=${server%]}
		PROTOS=6
	fi

	next_free_fd to_server_fd
	(
		eval "exec ${to_server_fd}<""'$to_server'"
		# Detect server proto:
		for proto in $PROTOS; do
			[ "$LOGLEVEL" -lt $INFO ] || err "Trying $server:$port (IPv$proto)..."
			if ip -$proto route get "$server" &>/dev/null; then
				# $server is an IP address
				ip_address=$server
				break
			else
				[ $proto -eq 6 ] && query=AAAA || query=A
				[ "$LOGLEVEL" -lt $INFO ] || err "Resolving $server (IPv$proto)..."
				ip_address=$(getent "ahostsv$proto" "$server" | awk '$2=="STREAM" { print $1}')
				[ "$ip_address" ] || continue
				[ "$LOGLEVEL" -lt $INFO ] || err "Resolved $server (IPv$proto) to $ip_address"
			fi

			[ "$LOGLEVEL" -lt $INFO ] || err "Connecting to $server:$port($ip_address)..."
			# Inform the reader about the proto. It'll prefix the HI/HELLO answer
			echo -n "$ip_address,$proto "
			$NETCAT "$ip_address" "$port" <&${to_server_fd} && exit || continue
			echo aa
		done
		exit
		die 1 "$server could not be resolved or it is not reachable"

	) | (
		eval "exec ${to_server_fd}>""'$to_server'"

		[ "$LOGLEVEL" -lt $INFO ] || err "Sending HI..."
		echo HI >&${to_server_fd}

		read -t2 server_info ||
			die 1 "Timeout waiting HI answer with '$server'"

		[ "$LOGLEVEL" -lt $TRACE ] ||
			err "Server info: '$server_info'"

		for ans in $server_info; do
			[ "$ans" != "HELLO" ] || break
			ip_address=${ans%,*}
			proto=${ans#*,}
		done
		[ "${ans}" = "HELLO" ] ||
			die 1 "BAD answer during HELLO with '$server': ${ans}"
		[ "$LOGLEVEL" -lt $INFO ] || err "Got HELLO"

		if [ "$test_PING" ]; then
			rtt_max=0
			rtt_min=99999
			rtt_sum=0
			rtt2_sum=0
			rtt_count=$PING_REPEAT
			[ "$LOGLEVEL" -lt $INFO ] || err "Sending $PING_REPEAT PING sequences"
			for i in $(seq $rtt_count); do
				t_ms=$($time_in_ms \
					${to_server_fd} \
					"echo PING $(date +%s)000" \
					"read -t2 -r ans" \
					'[ "${ans:0:4}" = "PONG" ]'
				) || die 1 "BAD answer during ping"

				rtt_sum=$((rtt_sum + t_ms))
				rtt2_sum=$((rtt2_sum + t_ms*t_ms))
				[ "$t_ms" -lt "$rtt_max" ] || rtt_max=$t_ms
				[ "$t_ms" -gt "$rtt_min" ] || rtt_min=$t_ms
			done
			rtt_mean=$(awkcalc '($1*1.0)/$2' "$rtt_sum" "$rtt_count")
			rtt_var=$(awkcalc '($1*1.0)/$2 - $3*$3' "$rtt2_sum" "$rtt_count" "$rtt_mean")
			rtt_stddev=$(awkcalc 'sqrt($1)' "$rtt_var")

			print_result "ping" "rtt_min" "seconds" "$(awkcalc '$1/1000' "$rtt_min")"
			print_result "ping" "rtt_mean" "seconds" "$(awkcalc '$1/1000' "$rtt_mean")"
			print_result "ping" "rtt_max" "seconds" "$(awkcalc '$1/1000' "$rtt_max")"
			print_result "ping" "rtt_stddev" "seconds" "$(awkcalc '$1/1000' "$rtt_stddev")"
		fi

		if [ "$test_DOWNLOAD" ]; then
			[ "$LOGLEVEL" -lt $INFO ] || err "Askig for $DOWNLOAD_SIZE bytes"
			for blocksize in 4096 2048 1024 512; do
				if [ $((DOWNLOAD_SIZE % blocksize)) -gt 0 ]; then
					[ "$LOGLEVEL" -lt $WARN ] || err "DOWNLOAD_SIZE=$DOWNLOAD_SIZE is not a multiple of blocksize=$blocksize"
					blocksize=""
				else
					break
				fi
			done
			[ "$blocksize" ] || [ "$LOGLEVEL" -lt $WARN ] || err "DOWNLOAD_SIZE=$DOWNLOAD_SIZE is not a multiple of 512"

			t_ms=$($time_in_ms \
				${to_server_fd} \
				"echo DOWNLOAD $DOWNLOAD_SIZE" \
				"dd ibs=$blocksize iflag=fullblock skip=$((DOWNLOAD_SIZE/blocksize)) count=0 of=/dev/null" \
			) &>/dev/null || die 1 "BAD answer during download"

			print_result "download" "payload" "bytes" "$DOWNLOAD_SIZE"
			print_result "download" "duration" "seconds" "$(awkcalc '$1/1000' "$t_ms")"
			print_result "download" "speed" "bytes_per_seconds" "$(awkcalc '$1/($2/1000)' "$DOWNLOAD_SIZE" "$t_ms")"
			print_result "download" "speed" "bits_per_seconds" "$(awkcalc '$1/($2/1000)*8' "$DOWNLOAD_SIZE" "$t_ms")"
		fi
		if [ "$test_UPLOAD" ]; then

			[ "$LOGLEVEL" -lt $INFO ] || err "Ofering $UPLOAD_SIZE bytes"

			cmd="UPLOAD $UPLOAD_SIZE 0"
			remaining_payload=$((UPLOAD_SIZE - (${#cmd}+1)))

			printf_args=""
			while true; do
				if [ "$remaining_payload" -gt $PRINTF_MAX_REPEAT ]; then
					printf_args="$printf_args $PRINTF_MAX_REPEAT 0"
					remaining_payload=$((remaining_payload - PRINTF_MAX_REPEAT))
				else
					printf_args="$remaining_payload 0"
					break
				fi
			done
			# FIXME: use random pattern, maybe using dd
			t_ms=$($time_in_ms \
				${to_server_fd} \
				"eval echo $cmd; printf %.*x $printf_args" \
				"read -r ans" \
				'[ "${ans:0:'"$((${#cmd}-5))"'}" = "OK $UPLOAD_SIZE " ]'
			) || die 1 "BAD answer during upload"

			print_result "upload" "payload" "bytes" "$UPLOAD_SIZE"
			print_result "upload" "duration" "seconds" "$(awkcalc '$1/1000' "$t_ms")"
			print_result "upload" "speed" "bytes_per_seconds" "$(awkcalc '$1/($2/1000)' "$UPLOAD_SIZE" "$t_ms")"
			print_result "upload" "speed" "bits_per_seconds" "$(awkcalc '$1/($2/1000)*8' "$UPLOAD_SIZE" "$t_ms")"

		fi

		[ "$LOGLEVEL" -lt $INFO ] || err "Sending QUIT"
		echo "QUIT" >&${to_server_fd}
		eval "exec ${to_server_fd}<&-"
	)
}

tempdir=$(mktemp -d -t speedtest.XXXXXXXX)
ls $tempdir
to_server="${tempdir}/to_server"
mkfifo "$to_server"
monitor_cpu &
monitor_cpu_pid=$!
trap "exit" INT TERM
trap "kill $monitor_cpu_pid 2>/dev/null; rm -rf '$tempdir'" EXIT

if [ -z "$SERVER" ]; then
	[ "$LOGLEVEL" -lt $INFO ] || err "No server defined. Looking for the best server"

	servers=$(
	if command -v wget &>/dev/null; then
		wget -O - -q "$SPEEDTEST_SERVERS"
	elif command -v curl &>/dev/null; then
		curl -sS "$SPEEDTEST_SERVERS"
	fi | sed -r 's/></>\n</g' | 
		awk '
			BEGIN { pregex="^[[:blank:]]*([a-zA-Z0-9]+)=\"([^\"]*)\"" }
			/^<\?/ {next}
			{ delete attr }
			{ tag=gensub(/>$/,"",1,gensub(/^</,"","1",$1)); $1="" }
			{ while (1) {
				key=gensub(pregex ".*","\\1","1",$0)
				if (key==$0) break
				value=gensub(pregex ".*","\\2","1",$0)
				$0=gensub(pregex,"","1",$0)
				attr[key]=value
			}}
			tag=="server" { printf "%s\t%s (%s/%s)\n", attr["host"], attr["sponsor"], attr["name"], attr["cc"]  }'
	)

	[ "$servers" ] ||
		die 1 "No servers found at '$SPEEDTEST_SERVERS'"

	best_latency_ms=9999999
	for _server in $(echo "$servers" | cut -f1); do
		latency=$(FORMAT=plain PING_REPEAT=2 test_server "$_server" PING | grep -E '^rtt_min'$'\t' | cut -f2)
		[ "$latency" ] || continue
		latency_ms=$(awkcalc 'int($1 * 1000)' $latency)
		[ "$LOGLEVEL" -lt $INFO ] || err "$_server: $latency_ms ms"
		if [ "$latency_ms" -lt "$best_latency_ms" ]; then
			best_latency_ms=$latency_ms
			server=$_server
		fi
	done
	[ "$server" ] || die 1 "No server reachable!"
	[ "$LOGLEVEL" -lt $INFO ] || err "Best Server: $(echo "$servers" | grep "^$server" | tr '\t' ' ') at $best_latency_ms ms"
else
	[ "$LOGLEVEL" -lt $INFO ] || err "Server defined as '$SERVER'"
	server=$SERVER
fi

if "$LIST_ONLY"; then
	echo "$server"
else
	test_server "$server" PING DOWNLOAD UPLOAD
fi
