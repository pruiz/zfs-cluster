#!/bin/bash

LC_ALL=C
LANG=C
PATH=/bin:/sbin:/usr/bin:/usr/sbin
export LC_ALL LANG PATH

. /usr/share/cluster/ocf-shellfuncs
. /usr/share/cluster/utils/iscsi-lib.sh

dump_variables() {
    for i in $(set |grep PMX | grep -v 'grep PMX')
    do \
            ocf_log info "iSCSI Helper: var => $i"
    done
}

autodetect_engine() {
    # Set a default implementation based on software installed
    if have_binary ietadm; then
        ENGINE="iet"
    elif have_binary tgtadm; then
        ENGINE="tgt"
    elif have_binary lio_node; then
        ENGINE="lio"
    else
        ocf_log err "No iSCSI engine found."
        exit $OCF_ERR_INSTALLED
    fi
}

create_config() {
    declare file=$1
cat > "${file}" <<__EOF
UUID=$2
TARGET=$3
LUN=$4
DEVICE=$5
BSTYPE=$6
VENDOR=$7
PRODUCT=$8
SCSIID=$9
SCSISN=${10}
EXTRAPARAMS=${11}
__EOF
}

get_next_lun() {
    declare dir=$1

    if [ -d "${dir}" -a ! -z "$(ls ${dir})" ]; then
        declare num=$(ls ${dir}/LUN-*|sed -e 's/^.*LUN-//'|sort -n|tail -n 1)
        if [ ! -z "${num}" ]; then
            echo $[$num+1] | tr -d ' '
            return;
        fi
    fi

    ## No luns yet, so let's start for the first available which
    ## on tgt, should be 1, as 0 is reserved for the target itself.
    case "${ENGINE}" in
      tgt) echo 1;;
      *) echo 0;;
    esac
}

add_lun() {
    declare cdir=
    declare target=
    declare device=
    declare bstype=aio
    declare vendor=
    declare product=
    declare scsiid=
    declare scsisn=
    declare extra=
    declare ARGS=$(getopt --long "cdir:,target:,device:,bstype:,vendor:,product:,scsiid:,scsisn:,extra:" -- "$@")
    declare rc=$OCF_SUCCESS

    eval set -- "$ARGS";
    while true; do 
        case "$1" in
            --cdir) cdir=$2; shift 2;;
            --target) target=$2; shift 2;;
            --device) device=$2; shift 2;;
            --bstype) bstype=$2; shift 2;;
            --vendor) vendor=$2; shift 2;;
            --product) product=$2; shift 2;;
            --scsiid) scsiid=$2; shift 2;;
            --scsisn) scsisn=$2; shift 2;;
            --extra) extra=$2; shift 2;;
            --) break ;;
            *) 
                ocf_log err "Invalid option: $1"
                exit $OCF_ERR_GENERIC
                ;;
        esac
    done

    for var in cdir target device; 
    do \
        if [ -z "${!var}" ]; then
            ocf_log err "Missing required argument: --${var}"
            exit $OCF_ERR_GENERIC
        fi
    done

    declare lun=$(get_next_lun "${cdir}/${target}")
    declare tmpfile=$(mktemp /tmp/LUN-${lun}-XXXXX)
    declare uuid=$(uuidgen)

    ocf_log debug "Using LUN: ${lun}"

    create_config "${tmpfile}" "${uuid}" "${target}" "${lun}" "${device}" \
        "${bstype}" "${vendor}" "${product}" "${scsiid}" "${scsisn}" "${extra}"

    iscsi_validate_config "${tmpfile}" "${target}"; rc=$?
    [ $rc -ne $OCF_SUCCESS ] && return $rc

    __iscsi_lun_status "${ENGINE}" "${target}" "${lun}" "${device}"; rc=$?
    if [ $rc -eq $OCF_SUCCESS ]; then
        ocf_log err "Device ${device} already shared."
        return $OCF_ERR_GENERIC
    elif [ $rc -ne $OCF_NOT_RUNNING ]; then
#        ocf_log err "Internal error while checking device status: $rc"
        return $rc
    fi

    iscsi_start_lun "${tmpfile}" "${ENGINE}"; rc=$?
    [ $rc -ne $OCF_SUCCESS ] && return $rc

    declare dir="${cdir}/${target}"
    cp "${tmpfile}" "${dir}/LUN-${lun}" || return $?

    ocf_log info "Created LUN-${lun} with uuid: ${uuid}"
    echo "Created LUN with uuid: ${uuid}"

    return $OCF_SUCCESS
}

del_lun() {
    declare cdir=
    declare target=
    declare device=
    declare uuid=
    declare ARGS=$(getopt --long "cdir:,target:,device:,uuid:" -- "$@")
    declare rc=$OCF_SUCCESS

    eval set -- "$ARGS";
    while true; do 
        case "$1" in
            --cdir) cdir=$2; shift 2;;
            --target) target=$2; shift 2;;
            --device) device=$2; shift 2;;
            --uuid) uuid=$2; shift 2;;
            --) break ;;
            *) 
                ocf_log err "Invalid option: $1"
                exit $OCF_ERR_GENERIC
                ;;
        esac
    done

    if [ ! -z "${device}" -a ! -z "${uuid}" ]; then
        ocf_log err "$FUNCNAME: Specifying both 'device' and 'uuid' not allowed."
        exit $OCF_ERR_GENERIC
    fi

    for var in cdir target; 
    do \
        if [ -z "${!var}" ]; then
            ocf_log err "$FUNCNAME: Missing required argument: --${var}"
            exit $OCF_ERR_GENERIC
        fi
    done

    declare tdir="${cdir}/${target}"
    if [ ! -d "${tdir}" ]; then
        ocf_log err "$FUNCNAME: No such target found: ${target}"
        exit $OCF_ERR_CONFIGURED
    fi

    declare lunfile=
    
    if [ ! -z "${device}" ]; then 
        lunfile=$(grep -l "^DEVICE=${device}$" "${tdir}"/LUN-* 2>/dev/null)
    elif [ ! -z "${uuid}" ]; then
        lunfile=$(grep -l "^UUID=${uuid}$" "${tdir}"/LUN-* 2>/dev/null)
    else
        ocf_log err "$FUNCNAME: Missing 'device' or 'uuid' argument."
        exit $OCF_ERR_GENERIC
    fi

    if [ -z "${lunfile}" ]; then
        ocf_log err "$FUNCNAME: No LUN found for: ${device}${uuid}"
        exit $OCF_ERR_CONFIGURED
    fi

    iscsi_validate_config "${lunfile}" "${target}"; rc=$?
    [ $rc -ne $OCF_SUCCESS ] && return $rc

    iscsi_lun_status "${lunfile}" "${ENGINE}" "${target}"; rc=$?
    ocf_log info "LUN status: $rc"
    if [ $rc -eq $OCF_SUCCESS ]; then
	ocf_log info "LUN is active, stopping it first.."
        ## Lun is being shared, remove it first.
        iscsi_stop_lun "${lunfile}" "${ENGINE}"; rc=$?
        [ $rc -ne $OCF_SUCCESS ] && return $rc
    elif [ $rc -ne $OCF_NOT_RUNNING ]; then
#        ocf_log err "Internal error while checking device status: $rc"
        return $rc
    fi

    rm -f "${lunfile}" || return $?

    return $OCF_SUCCESS
}

get_uuid() {
    declare cdir=
    declare target=
    declare device=
    declare ARGS=$(getopt --long "cdir:,target:,device:" -- "$@")
    declare rc=$OCF_SUCCESS

    eval set -- "$ARGS";
    while true; do 
        case "$1" in
            --cdir) cdir=$2; shift 2;;
            --target) target=$2; shift 2;;
            --device) device=$2; shift 2;;
            --) break ;;
            *) 
                ocf_log err "Invalid option: $1"
                exit $OCF_ERR_GENERIC
                ;;
        esac
    done

    for var in cdir target device target; 
    do \
        if [ -z "${!var}" ]; then
            ocf_log err "$FUNCNAME: Missing required argument: --${var}"
            exit $OCF_ERR_GENERIC
        fi
    done

    declare tdir="${cdir}/${target}"
    if [ ! -d "${tdir}" ]; then
        ocf_log err "$FUNCNAME: No such target found: ${target}"
        exit $OCF_ERR_CONFIGURED
    fi

    declare lunfile=$(grep -l "^DEVICE=${device}$" "${tdir}"/LUN-* 2>/dev/null)
    if [ -z "${lunfile}" ]; then
        ocf_log err "$FUNCNAME: No LUN found for: ${device}"
        exit $OCF_ERR_CONFIGURED
    fi

    iscsi_validate_config "${lunfile}" "${target}"; rc=$?
    [ $rc -ne $OCF_SUCCESS ] && return $rc

    eval $(__source_config "${lunfile}")
    if [ -z "$UUID" ]; then
        ocf_log err "$FUNCNAME: Lun has no Unique Id"
        exit $OCF_ERR_CONFIGURED
    fi

    echo "LUN UUID: ${UUID}"
    
    return $OCF_SUCCESS
}

get_lun() {
    declare cdir=
    declare target=
    declare device=
    declare uuid=
    declare ARGS=$(getopt --long "cdir:,target:,device:" -- "$@")
    declare rc=$OCF_SUCCESS

    eval set -- "$ARGS";
    while true; do 
        case "$1" in
            --cdir) cdir=$2; shift 2;;
            --target) target=$2; shift 2;;
            --device) device=$2; shift 2;;
            --uuid) uuid=$2; shift 2;;
            --) break ;;
            *) 
                ocf_log err "Invalid option: $1"
                exit $OCF_ERR_GENERIC
                ;;
        esac
    done

    for var in cdir target; 
    do \
        if [ -z "${!var}" ]; then
            ocf_log err "$FUNCNAME: Missing required argument: --${var}"
            exit $OCF_ERR_GENERIC
        fi
    done

    if [ ! -z "${device}" -a ! -z "${uuid}" ]; then
        ocf_log err "$FUNCNAME: Specifying both 'device' and 'uuid' not allowed."
        exit $OCF_ERR_GENERIC
    fi

    declare tdir="${cdir}/${target}"
    if [ ! -d "${tdir}" ]; then
        ocf_log err "$FUNCNAME: No such target found: ${target}"
        exit $OCF_ERR_CONFIGURED
    fi

    declare lunfile=
    
    if [ ! -z "${device}" ]; then 
        lunfile=$(grep -l "^DEVICE=${device}$" "${tdir}"/LUN-* 2>/dev/null)
    elif [ ! -z "${uuid}" ]; then
        lunfile=$(grep -l "^UUID=${uuid}$" "${tdir}"/LUN-* 2>/dev/null)
    else
        ocf_log err "$FUNCNAME: Missing 'device' or 'uuid' argument."
        exit $OCF_ERR_GENERIC
    fi

    if [ -z "${lunfile}" ]; then
        ocf_log err "$FUNCNAME: No LUN found for: ${device}${uuid}"
        exit $OCF_ERR_CONFIGURED
    fi

    iscsi_validate_config "${lunfile}" "${target}"; rc=$?
    [ $rc -ne $OCF_SUCCESS ] && return $rc

    eval $(__source_config "${lunfile}")
    if [ -z "$LUN" ]; then
        ocf_log err "$FUNCNAME: Lun has no number"
        exit $OCF_ERR_CONFIGURED
    fi

    echo "LUN: ${LUN}"
    
    return $OCF_SUCCESS
}

reshare_lun() {
    declare cdir=
    declare target=
    declare device=
    declare uuid=
    declare ARGS=$(getopt --long "cdir:,target:,device:,uuid:" -- "$@")
    declare rc=$OCF_SUCCESS

    eval set -- "$ARGS";
    while true; do 
        case "$1" in
            --cdir) cdir=$2; shift 2;;
            --target) target=$2; shift 2;;
            --device) device=$2; shift 2;;
            --uuid) uuid=$2; shift 2;;
            --) break ;;
            *) 
                ocf_log err "Invalid option: $1"
                exit $OCF_ERR_GENERIC
                ;;
        esac
    done

    if [ ! -z "${device}" -a ! -z "${uuid}" ]; then
        ocf_log err "$FUNCNAME: Specifying both 'device' and 'uuid' not allowed."
        exit $OCF_ERR_GENERIC
    fi

    for var in cdir target; 
    do \
        if [ -z "${!var}" ]; then
            ocf_log err "$FUNCNAME: Missing required argument: --${var}"
            exit $OCF_ERR_GENERIC
        fi
    done

    declare tdir="${cdir}/${target}"
    if [ ! -d "${tdir}" ]; then
        ocf_log err "$FUNCNAME: No such target found: ${target}"
        exit $OCF_ERR_CONFIGURED
    fi

    declare lunfile=
    
    if [ ! -z "${device}" ]; then 
        lunfile=$(grep -l "^DEVICE=${device}$" "${tdir}"/LUN-* 2>/dev/null)
    elif [ ! -z "${uuid}" ]; then
        lunfile=$(grep -l "^UUID${uuid}$" "${tdir}"/LUN-* 2>/dev/null)
    else
        ocf_log err "$FUNCNAME: Missing 'device' or 'uuid' argument."
        exit $OCF_ERR_GENERIC
    fi

    if [ -z "${lunfile}" ]; then
        ocf_log err "$FUNCNAME: No LUN found for: ${device}${uuid}"
        exit $OCF_ERR_CONFIGURED
    fi

    iscsi_validate_config "${lunfile}" "${target}"; rc=$?
    [ $rc -ne $OCF_SUCCESS ] && return $rc

    iscsi_lun_status "${lunfile}" "${ENGINE}" "${target}"; rc=$?
    if [ $rc -eq $OCF_SUCCESS ]; then
        ## Lun is being shared, remove it first.
        iscsi_stop_lun "${lunfile}" "${ENGINE}"; rc=$?
        [ $rc -ne $OCF_SUCCESS ] && return $rc
    fi

    iscsi_start_lun "${lunfile}" "${ENGINE}"; rc=$?

    return $rc
}


###### Main ######

i=1
ocf_log info "iSCSI Helper running with: "
for arg in "$@"
do
    ocf_log info "ARG[$i]: ${!i}"
    i=$[$i+1]
done

#dump_variables
autodetect_engine

case "$1" in
  add-lun) 
    add_lun $@
    ;;
  del-lun)
    del_lun $@
    ;;
  get-uuid)
    get_uuid $@
    ;;
  get-lun)
    get_lun $@
    ;;
  reshare-lun)
    reshare_lun $@
    ;;
  *)
    ocf_log err "Invalid command: $1"
    exit 255
    ;;
esac

exit $?

