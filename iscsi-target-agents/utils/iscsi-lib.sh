#!/bin/bash

# Make sure PATH contains all the usual suspects
PATH="$PATH:/sbin:/bin:/usr/sbin:/usr/bin"

# Include /usr/ucb for finding whoami on Solaris
PATH="$PATH:/usr/ucb"

export PATH

if [ "$OCF_SUCCESS" -ne "0" ]
then \
	echo "Missing ocfshell includes." 1>&2
	exit 255
fi

# Binaries and binary options for use in Resource Agents
: ${AWK:=gawk}
: ${EGREP:="/bin/grep -E"}
: ${IFCONFIG_A_OPT:="-a"}
: ${MAILCMD:=mail}
: ${PING:=/bin/ping}
: ${SH:=/bin/sh}
: ${TEST:=/usr/bin/test}
: ${TESTPROG:=/usr/bin/test}

# Entries that should probably be removed
: ${BASENAME:=basename}
: ${BLOCKDEV:=blockdev}
: ${CAT:=cat}
: ${FSCK:=fsck}
: ${FUSER:=fuser}
: ${GETENT:=getent}
: ${GREP:=grep}
: ${IFCONFIG:=ifconfig}
: ${IPTABLES:=iptables}
: ${IP2UTIL:=ip}
: ${MDADM:=mdadm}
: ${MODPROBE:=modprobe}
: ${MOUNT:=mount}
: ${MSGFMT:=msgfmt}
: ${NETSTAT:=netstat}
: ${PERL:=perl}
: ${PYTHON:=python}
: ${RAIDSTART:=raidstart}
: ${RAIDSTOP:=raidstop}
: ${ROUTE:=route}
: ${UMOUNT:=umount}
: ${REBOOT:=reboot}
: ${POWEROFF_CMD:=poweroff}
: ${WGET:=wget}
: ${WHOAMI:=whoami}
: ${STRINGSCMD:=strings}
: ${SCP:=scp}
: ${SSH:=ssh}
: ${SWIG:=swig}
: ${GZIP_PROG:=gzip}
: ${TAR:=tar}
: ${MD5:=md5}
: ${DRBDADM:=drbdadm}
: ${DRBDSETUP:=drbdsetup}

# Define OCF_RESKEY_CRM_meta_interval in case it isn't already set,
# to make sure that ocf_is_probe() always works
: ${OCF_RESKEY_CRM_meta_interval=0}

check_binary () {
    if ! have_binary "$1"; then
	if [ "$OCF_NOT_RUNNING" = 7 ]; then
	    # Chances are we have a fully setup OCF environment
	    ocf_log err "Setup problem: couldn't find command: $1"
	else 
	    echo "Setup problem: couldn't find command: $1"
	fi
	exit $OCF_ERR_INSTALLED
    fi
}

have_binary () {
    if [ "$OCF_TESTER_FAIL_HAVE_BINARY" = "1" ]; then
    	false
    else
	local bin=`echo $1 | sed -e 's/ -.*//'`
	test -x "`which $bin 2>/dev/null`"
    fi
}

# returns true if the CRM is currently running a probe. A probe is
# defined as a monitor operation with a monitoring interval of zero.
ocf_is_probe() {
    [ "$__OCF_ACTION" = "monitor" -a "$OCF_RESKEY_CRM_meta_interval" = 0 ]
}

#
# Ocf_run: Run a script, and log its output.
# Usage:   ocf_run [-q] [-info|-warn|-err] <command>
#       -q: don't log the output of the command if it succeeds
#       -info|-warn|-err: log the output of the command at given
#               severity if it fails (defaults to err)
#
ocf_run() {
        local rc
        local output
        local verbose=1
        local loglevel=err
        local var

        for var in 1 2
        do
            case "$1" in
                "-q")
                    verbose=""
                    shift 1;;
                "-info"|"-warn"|"-err")
                    loglevel=`echo $1 | sed -e s/-//g`
                    shift 1;;
                *)
                    ;;
            esac
        done

        output=`"$@" 2>&1`
        rc=$?
        output=`echo $output`
        if [ $rc -eq 0 ]; then
            if [ "$verbose" -a ! -z "$output" ]; then
                ocf_log info "$output"
            fi
            return $OCF_SUCCESS
        else
            ocf_log $loglevel "command failed: $* (output: $output)"
            return $rc
        fi
}

__iscsi_validate() {
    declare NAME=$1
    declare ENGINE=$2
    declare TARGET=$3
    declare LUN=$4
    declare DEVICE=$5
    
    # Do we have all required variables?
    for var in NAME ENGINE TARGET LUN DEVICE; do
	param="${var}"
	if [ -z "${!param}" ]; then
	    ocf_log error "Missing resource parameter \"$var\"!"
	    exit $OCF_ERR_CONFIGURED
	fi
    done

    # Is the configured implementation supported?
    case "$ENGINE" in
	iet|tgt|lio)
	    ;;
	*)
	    ocf_log error "Unsupported iSCSI target implementation \"$ENGINE\"!"
	    exit $OCF_ERR_CONFIGURED
    esac

    # Do we have a valid LUN?
    case "$ENGINE" in
	iet)
	    # IET allows LUN 0 and up
	    [ $LUN -ge 0 ]
	    case $? in
		0)
	            # OK
		    ;;
		1)
		    ocf_log err "Invalid LUN $LUN (must be a non-negative integer)."
		    exit $OCF_ERR_CONFIGURED
		    ;;
		*)
		    ocf_log err "Invalid LUN $LUN (must be an integer)."
		    exit $OCF_ERR_CONFIGURED
		    ;;
	    esac
	    ;;
	tgt)
	    # tgt reserves LUN 0 for its own purposes
	    [ $LUN -ge 1 ]
	    case $? in
		0)
	            # OK
		    ;;
		1)
		    ocf_log err "Invalid LUN $LUN (must be greater than 0)."
		    exit $OCF_ERR_CONFIGURED
		    ;;
		*)
		    ocf_log err "Invalid LUN $LUN (must be an integer)."
		    exit $OCF_ERR_CONFIGURED
		    ;;
	    esac
	    ;;
    esac

    if ! ocf_is_probe; then
    # Do we have all required binaries?
	case $ENGINE in
	    iet)
		check_binary ietadm
		;;
	    tgt)
		check_binary tgtadm
		;;
	    lio)
		check_binary tcm_node
		check_binary lio_node
		;;
	esac

        # Is the required kernel functionality available?
	case $ENGINE in
	    iet)
		[ -d /proc/net/iet ]
		if [ $? -ne 0 ]; then
		    ocf_log err "/proc/net/iet does not exist or is not a directory -- check if required modules are loaded."
		    exit $OCF_ERR_INSTALLED
		fi
		;;
	    tgt)
	        # tgt is userland only
		;;
	esac
    fi

    return $OCF_SUCCESS
}

iscsi_get_tid() {
    declare ENGINE=$1
    declare IQN=$2
    declare TID

    if [ -z "$ENGINE" ]; then
	ocf_log err "$FUNCNAME: Missing engine parameter"
	exit $OCF_ERR_GENERIC
    fi

    if [ -z "$IQN" ]; then
	ocf_log err "$FUNCNAME: Missing IQN parameter"
	exit $OCF_ERR_GENERIC
    fi

    case "$ENGINE" in
	iet)
 	    # Figure out and set the target ID
	    TID=`sed -ne "s/tid:\([[:digit:]]\+\) name:${IQN}/\1/p" < /proc/net/iet/volume`
	    if [ -z "${TID}" ]; then
		# Our target is not configured, thus we're not
		# running.
		return $OCF_NOT_RUNNING
	    fi
	    ;;
	tgt)
	    # Figure out and set the target ID
	    TID=`tgtadm --lld iscsi --op show --mode target \
		| sed -ne "s/^Target \([[:digit:]]\+\): ${IQN}/\1/p"`
	    if [ -z "$TID" ]; then
		# Our target is not configured, thus we're not
		# running.
		return $OCF_NOT_RUNNING
	    fi
	    ;;
	lio)
	    ocf_log err "LIO support not yet implemented."
	    return $OCF_ERR_UNIMPLEMENTED
	    ;;
        *)
            ocf_log err "Unsupported iSCSI engine: $ENGINE"
	    return $OCF_ERR_GENERIC;
	    ;;
    esac
   
    echo "$TID"
    return $OCF_SUCCESS
}

__iscsi_lun_status() {
    declare ENGINE=$1
    declare TARGET=$2
    declare LUN=$3
    declare DEVICE=$4

    if [ -z "$ENGINE" ]; then
	ocf_log err "$FUNCNAME: Missing engine argument"
	return $OCF_ERR_GENERIC
    fi

    if [ -z "$TARGET" ]; then
	ocf_log err "$FUNCNAME: Missing target argument"
	return $OCF_ERR_GENERIC
    fi

    if [ -z "$LUN" ]; then
	ocf_log err "$FUNCNAME: Missing lun argument"
	return $OCF_ERR_GENERIC
    fi

    if [ -z "$DEVICE" ]; then
	ocf_log err "$FUNCNAME: Missing device argument"
	return $OCF_ERR_GENERIC
    fi

    case "$ENGINE" in
	iet)
            # FIXME: this looks for a matching LUN and path, but does
            # not actually test for the correct target ID.
            grep -E -q "[[:space:]]+lun:${LUN}.*path:${DEVICE}$" /proc/net/iet/volume && return $OCF_SUCCESS
	    ;;
	tgt)
            # This only looks for the backing store, but does not test
            # for the correct target ID and LUN.
            tgtadm --lld iscsi --op show --mode target \
                | grep -E -q "[[:space:]]+Backing store.*: ${DEVICE}$" && return $OCF_SUCCESS
            ;;
	lio)
            configfs_path="/sys/kernel/config/target/iscsi/${TARGET}/tpgt_1/lun/lun_${LUN}/${OCF_RESOURCE_INSTANCE}/udev_path"
            [ -e ${configfs_path} ] && [ `cat ${configfs_path}` = "${OCF_RESKEY_path}" ] && return $OCF_SUCCESS
	    ;;
        *)
            ocf_log err "$FUNCNAME: Unsupported iSCSI engine: $ENGINE" 2>&1
	    return $OCF_ERR_GENERIC;
	    ;;
    esac

    return $OCF_NOT_RUNNING
}

__iscsi_add_lun() {
    declare ENGINE=$1
    declare TARGET=$2
    declare LUN=$3
    declare DEVICE=$4
    declare vendor_id=$5
    declare product_id=$6
    declare scsi_id=$7
    declare scsi_sn=$8
    declare bstype=$9
    declare bsoflags=${10}
    declare EXTRAPARAMS="${11}"
    declare TID=$(iscsi_get_tid "${ENGINE}" "${TARGET}")
    declare rc=$OCF_SUCCESS

    if [ -z "$TID" ]; then
        ocf_log err "$FUNCNAME: No target ${TARGET} found."
	return $OCF_ERR_CONFIGURED
    fi

    if [ -z "$DEVICE" ]; then
	ocf_log err "Missing device argument"
	return $OCF_ERR_GENERIC
    fi

    __iscsi_lun_status "$ENGINE" "$TARGET" "$LUN" "$DEVICE"; rc=$?

    if [ $rc -eq $OCF_SUCCESS ]; then
        ocf_log info "LUN ($DEVICE) already shared."
        return $OCF_SUCCESS
    elif [ $rc -ne $OCF_NOT_RUNNING ]; then
        ocf_log err "Checking LUN ($DEVICE) status failed: $rc"
        return $rc
    fi

    if [ -z "${scsi_id}" ]; then
        scsi_id=$(basename ${DEVICE})
    fi

    if [ -z "${scsi_sn}" ]; then
        scsi_sn=`echo -n "${scsi_id}" | md5sum`
        scsi_sn=${scsi_sn:0:8}
    fi

    local params

    case "$ENGINE" in
	iet)
	    params="Path=${DEVICE}"
	    # use blockio if path points to a block device, fileio
	    # otherwise.
	    if [ -b "${DEVICE}" ]; then
		params="${params} Type=blockio"
	    else
		params="${params} Type=fileio"
	    fi
	    # in IET, we have to set LU parameters on creation
	    if [ -n "${scsi_id}" ]; then
		params="${params} ScsiId=${scsi_id}"
	    fi
	    if [ -n "${scsi_sn}" ]; then
		params="${params} ScsiSN=${scsi_sn}"
	    fi
	    params="${params} ${EXTRAPARAMS}"
	    ocf_run ietadm --op new \
		--tid=${TID} \
		--lun=${LUN} \
		--params ${params// /,} || exit $OCF_ERR_GENERIC
	    ;;
	tgt)
	    # tgt requires that we create the LU first, then set LU
	    # parameters
	    params=""
	    local var
            local envar
	    for var in scsi_id scsi_sn vendir_id product_id; do
		envar="${var}"
		if [ -n "${!envar}" ]; then
		    params="${params} ${var}=${!envar}"
		fi
	    done
	    params="${params} ${EXTRAPARAMS}"
	    if [ -n "$bstype" ]; then
		bstype="--bstype=${bstype}"
	    fi
            if [ -n "$bsoflags" ]; then
		bsoflags="--bsoflags=${bsoflags}"
            fi  
	    ocf_log info "Starting LUN: ${LUN} (@${TID}) using ${DEVICE} as ${bstype} ${bsoflags} (extra: ${params})\n"
	    ocf_run tgtadm --lld iscsi --op new --mode logicalunit \
		--tid=${TID} \
		--lun=${LUN} \
	    	--backing-store ${DEVICE} ${bstype} ${bsoflags} || exit $OCF_ERR_GENERIC
	    if [ -z "$params" ]; then
		return $OCF_SUCCESS
	    else
		ocf_run tgtadm --lld iscsi --op update --mode logicalunit \
		    --tid=${TID} \
		    --lun=${LUN} \
		    --params ${params// /,} || exit $OCF_ERR_GENERIC
	    fi
	    ;;
	lio)
	    # For lio, we first have to create a target device, then
	    # add it to the Target Portal Group as an LU.
	    ocf_run tcm_node --createdev=iblock_0/${OCF_RESOURCE_INSTANCE} \
		${DEVICE} || exit $OCF_ERR_GENERIC
	    if [ -n "${OCF_RESKEY_scsi_sn}" ]; then
		ocf_run tcm_node --setunitserial=iblock_0/${OCF_RESOURCE_INSTANCE} \
		    ${scsi_sn} || exit $OCF_ERR_GENERIC
	    fi
	    ocf_run lio_node --addlun=${TARGET} 1 ${LUN} \
		${OCF_RESOURCE_INSTANCE} iblock_0/${OCF_RESOURCE_INSTANCE} || exit $OCF_ERR_GENERIC

	    ;;
    esac

    return $OCF_SUCCESS
}

__iscsi_del_lun() {
    declare ENGINE=$1
    declare TARGET=$2
    declare LUN=$3
    declare DEVICE=$4
    declare TID=$(iscsi_get_tid "${ENGINE}" "${TARGET}")
    declare rc=$OCF_SUCCESS

    if [ -z "$TID" ]; then
        ocf_log err "$FUNCNAME: No target ${TARGET} found."
	return $OCF_ERR_CONFIGURED
    fi

    if [ -z "$DEVICE" ]; then
	ocf_log err "$FUNCNAME: Missing device argument"
	return $OCF_ERR_GENERIC
    fi

    __iscsi_lun_status "$ENGINE" "$TARGET" "$LUN" "$DEVICE"; rc=$?

    if [ $rc -eq $OCF_NOT_RUNNING ]; then
        ocf_log info "LUN ($DEVICE) not shared."
        return $OCF_SUCCESS
    elif [ $rc -ne $OCF_SUCCESS ]; then
        ocf_log err "Checking LUN ($DEVICE) status failed: $rc"
        return $rc
    fi

    local params

    case "$ENGINE" in
	iet)
            # IET allows us to remove LUs while they are in use
            ocf_run ietadm --op delete \
                --tid=${TID} \
                --lun=${LUN} || exit $OCF_ERR_GENERIC
            ;;
        tgt)
            # tgt will fail to remove an LU while it is in use,
            # but at the same time does not allow us to
            # selectively shut down a connection that is using a
            # specific LU. Thus, we need to loop here until tgtd
            # decides that the LU is no longer in use, or we get
            # timed out by the LRM.
            while ! ocf_run -warn tgtadm --lld iscsi --op delete --mode logicalunit \
                --tid ${TID} \
                --lun=${LUN}; do
                sleep 1
            done
            ;;
	lio)
            ocf_run lio_node --dellun=${TARGET} 1 ${LUN} || exit $OCF_ERR_GENERIC
            ocf_run tcm_node --freedev=iblock_0/${OCF_RESOURCE_INSTANCE} || exit $OCF_ERR_GENERIC
            ;;
    esac
    
    return $OCF_SUCCESS
}

__source_config() {
    sed -e 's/\([^#]*\)#.*$/\1/g' -e '/^\s*$/d' -e 's,^,declare ,g' -e 's,$,;,g' "$1"
}

iscsi_validate_config() {
    declare CONFIGFILE=$1
    declare _target=$2  ## Optional
    declare _lun=$(basename "${CONFIGFILE}" | sed -e 's,^LUN-\([0-9]\+\).*,\1,g')
    eval $(__source_config "${CONFIGFILE}")

    if [ -z "${TARGET}" ]; then
        ocf_log err "$FUNCNAME: Invalid LUN config file: Missing TARGET variable."
        return $OCF_ERR_CONFIGURED
    fi

    if [ ! -z "${_target}" -a "${TARGET}" != "${_target}" ]; then
        ocf_log err "$FUNCNAME: Invalid LUN config file: Target does not match expected."
        return $OCF_ERR_CONFIGURED
    fi

    if [ -z "${LUN}" ]; then
        ocf_log err "$FUNCNAME: Invalid LUN config file: Missing LUN variable."
        return $OCF_ERR_CONFIGURED
    fi

    if [ "${LUN}" -ne "${_lun}" ]; then
        ocf_log err "$FUNCNAME: Invalid LUN config file: Lun number does not match filename."
        return $OCF_ERR_CONFIGURED
    fi

    if [ -z "${DEVICE}" ]; then
        ocf_log err "$FUNCNAME: Invalid LUN config file: Missing DEVICE variable."
        return $OCF_ERR_CONFIGURED
    fi

    return $OCF_SUCCESS
}


iscsi_start_lun() {
    declare CONFIGFILE=$1
    declare engine=$2
    declare target=$3
    declare rc=0

    iscsi_validate_config "${CONFIGFILE}" "${target}" ; rc=$?
    [ $rc -ne $OCF_SUCCESS ] && return $rc

    eval $(__source_config "${CONFIGFILE}")
    __iscsi_add_lun "${engine}" "${TARGET}" "${LUN}" "${DEVICE}" \
                    "${VENDOR}" "${PRODUCT}" "${SCSIID}" "${SCSISN}" "${BSTYPE}" "${BSOFLAGS}" \
                    "${EXTRAPARAMS}"
    return $?
}

iscsi_stop_lun() {
    declare CONFIGFILE=$1
    declare engine=$2
    declare target=$3
    declare rc=0

    iscsi_validate_config "${CONFIGFILE}" "${target}" ; rc=$?
    [ $rc -ne $OCF_SUCCESS ] && return $rc

    eval $(__source_config "${CONFIGFILE}")
    __iscsi_del_lun "${engine}" "${TARGET}" "${LUN}" "${DEVICE}"
    return $?
}

iscsi_lun_status() {
    declare CONFIGFILE=$1
    declare engine=$2
    declare target=$3
    declare rc=$?

    iscsi_validate_config "${CONFIGFILE}" "${target}" ; rc=$?
    [ $rc -ne $OCF_SUCCESS ] && return $rc

    eval $(__source_config "${CONFIGFILE}")
    __iscsi_lun_status "${engine}" "${TARGET}" "${LUN}" "${DEVICE}"
    return $?
}

