#!/bin/bash

LC_ALL=C
LANG=C
PATH=/bin:/sbin:/usr/bin:/usr/sbin
export LC_ALL LANG PATH

CFGDIR=$(dirname $0)
HELPER=/usr/lib/ocf/lib/netway/iscsi-helper.sh

. /usr/lib/ocf/lib/heartbeat/ocf-shellfuncs

dump_variables() {
    for i in $(set |grep PMX | grep -v 'grep PMX')
    do \
            ocf_log info "iSCSI Helper: var => $i"
    done
}

create_lun() {
    declare OUTPUT=$("$HELPER" add-lun "--cdir=$CFGDIR" "--target=${PMXCFG_target}" "--device=$1" |grep 'Created LUN with uuid:')
    [ $? -ne 0 ] && exit $?
    declare UUID=$(echo "$OUTPUT"|sed -e 's,Created LUN with uuid: ,,g')
    [ -z "$UUID" ] && exit 255
    echo $UUID
    return 0
}

delete_lun() {
    "$HELPER" del-lun "--cdir=$CFGDIR" "--target=${PMXCFG_target}" "--uuid=$1" > /dev/null 
    return $?
}

get_lun_uuid() {
    declare OUTPUT=$("$HELPER" get-uuid "--cdir=$CFGDIR" "--target=${PMXCFG_target}" "--device=$1"|grep 'LUN UUID: ')
    [ $? -ne 0 ] && exit $?
    declare UUID=$(echo "$OUTPUT"|sed -e 's,^LUN UUID: ,,g')
    [ -z "$UUID" ] && exit 255
    echo $UUID
    return 0
}

get_lun_number() {
    declare OUTPUT=$("$HELPER" get-lun "--cdir=$CFGDIR" "--target=${PMXCFG_target}" "--uuid=$1"|grep 'LUN: ')
    [ $? -ne 0 ] && exit $?
    declare LUN=$(echo "$OUTPUT"|sed -e 's,^LUN: ,,g')
    [ -z "$LUN" ] && exit 255
    echo $LUN
    return 0
}

resize_lun() {
    "$HELPER" reshare-lun "--cdir=$CFGDIR" "--target=${PMXCFG_target}" "--uuid=$1" > /dev/null 
    return $?
}

# Backwards compat..

if [ -z "${PMXCFG_target}" ]
then \
	export PMXCFG_target=${PMXVAR_TARGET}
fi

if [ -z "${PMXCFG_pool}" ]
then \
	export PMXCFG_pool=${PMXVAR_POOL}
fi

case "$1" in
  create-lu) shift; create_lun $@;;
  delete-lu) shift; delete_lun $@;;
  share-lu) ;; # Do nothing.
  import-lu) shift; create_lun $@;;
  get-lu-id) shift; get_lun_uuid $@;;
  get-lu-no) shift; get_lun_number $@;;

  create-lun) shift; create_lun $@;;
  delete-lun) shift; delete_lun $@;;
  list-lun) shift; get_lun_uuid $@;;
  list-view) shift; get_lun_number $@;;
  add-view)
	## Do nothing..
	;;
  resize-lu) shift; resize_lun $@;;
  *)
        ocf_log err "Invalid command: $1"
        exit 255
        ;;
esac

exit $?
