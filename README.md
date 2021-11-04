# speedtest-shell
This is an unofficial speedtest (ookla) client, compatible with most basic systems, including OpenWrt routers.

It is a very simple but useful speedtest, designed to be executed from a OpenWrt router, but possibly compatible with most
UNIX systems with minor changes.

```
Usage speedtest-cli.sh [ -4 | -6 ] [ -c ( nc | netcat | socat ) ] [ -d bytes ] [ -i times ]
      [-I device] [ -p port ] [ -s server] [ -u bytes ]

Runs a speedtest 

Options:
 -4     Connect only to IPv4 servers. Default is IPv6 or IPv4.
 -6     Connect only to IPv6 servers Default is IPv6 or IPv4.
 -c     Define the netcat client. By default, it tries, socat, netcat and nc
 -d     Define the download payload size in bytes. Default is 52428800
 -i     Define number of times a PING command is issued. Default is 10
 -I     Bind to interface (only works with socat)
 -l     List close servers
 -s     Define the server address (name or ip address) with port. IPv6 addresses
        needs to use braces, like in URL. Default is to look for the fastest server.
 -u     Define the upload payload size in bytes; Default is 20971520
 -v     Be verbose

If not server was provided, it will look for the best one at:
 https://www.speedtest.net/speedtest-servers-static.php
```

It requires a web client (curl or wget), a tcp client (socat, netcat or nc) and a POSIX shell (tested with ash and bash). It also requires some basic unix tools like sed, awk, dd, tr, grep, cut, nslookup, ip

If no server is specified, it gets a list of servers from https://www.speedtest.net/speedtest-servers-static.php, choose the closest one (based on the server answers) and run a test. The standard est is executed through a TCP connection. First, it pings the server (through the TCP connection) and then download 50M and upload 20M.

As a shell script, this client has its limitations. I could not test anything over 170 Mbps but I cannot garantee this is the connection, target server or script limit. For slow CPU devices, like many OpenWrt routers, that limit would be even lower. If the script detects the CPU is at 100%, it will 
give you a warning ("CPU is struggling... expect worse measures"). With slow CPUs, the socat seems to be the best option.

It uses either /proc/timer_list or /proc/uptime to measue time, although uptime resolution is in cs (1/100s). For very close servers and the time in cs, expect strange things like 0ms RTT.

I cannot garantee the acuracy of this client but there is a good confidence that the real speed is equal or faster than the reported by the script, not slower.

Some runs:

```
# Internet 120 Mbps/12 Mbps
root@router-slow:~# speedtest-cli.sh
ping.rtt_min = 0 ms
ping.rtt_mean = 6 ms
ping.rtt_max = 10 ms
ping.rtt_stddev = 4 ms
CPU is struggling... expect worse measures
download.payload = 50.0000 MiB 52.4288 MB
download.duration = 7.340000 s
download.speed = 6.8120 MiB/s 7.1429 MB/s
download.speed = 54.4959 Mib/s 57.1431 Mb/s
upload.payload = 20.0000 MiB 20.9715 MB
upload.duration = 5.740000 s
upload.speed = 3.4843 MiB/s 3.6536 MB/s
upload.speed = 27.8746 Mib/s 29.2286 Mb/s

# Internet 300 Mbps/300 Mbps
root@router-fast:~# speedtest-cli.sh
ping.rtt_min = 0 ms
ping.rtt_mean = 3 ms
ping.rtt_max = 10 ms
ping.rtt_stddev = 4 ms
download.payload = 50.0000 MiB 52.4288 MB
download.duration = 2.330000 s
download.speed = 21.4592 MiB/s 22.5016 MB/s
download.speed = 171.6738 Mib/s 180.0130 Mb/s
upload.payload = 20.0000 MiB 20.9715 MB
upload.duration = 0.880000 s
upload.speed = 22.7273 MiB/s 23.8313 MB/s
upload.speed = 181.8180 Mib/s 190.6500 Mb/s

# Internet 120 Mbps/12 Mbps
user@linux-desktop:~# speedtest-cli.sh
ping.rtt_min = 10 ms
ping.rtt_mean = 16 ms
ping.rtt_max = 30 ms
ping.rtt_stddev = 6 ms
download.payload = 50.0000 MiB 52.4288 MB
download.duration = 3.400000 s
download.speed = 14.7058 MiB/s 15.4202 MB/s
download.speed = 117.6472 Mib/s 123.3620 Mb/s
upload.payload = 20.0000 MiB 20.9715 MB
upload.duration = 16.040000 s
upload.speed = 1.2469 MiB/s 1.3075 MB/s
upload.speed = 9.9751 Mib/s 10.4596 Mb/s
```
