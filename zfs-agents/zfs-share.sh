#!/bin/sh

case "$1" in
        start)
		/sbin/zfs share -a
                exit 0;;
        stop)
		/sbin/zfs unshare -a
                exit 0;;
	status)
		exit 0;;
        *)      
		echo "Usage: $0 [start|stop]"  >&2
                exit 1;;
esac
