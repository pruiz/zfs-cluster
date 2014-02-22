#!/bin/bash

LC_ALL=C
LANG=C
PATH=/bin:/sbin:/usr/bin:/usr/sbin
export LC_ALL LANG PATH

CFGDIR=$(dirname $0)
HELPER=/usr/share/cluster/utils/iscsi-helper.sh

. /usr/share/cluster/ocf-shellfuncs

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
    "$HELPER" del-lun "--cdir=$CFGDIR" "--target=${PMXCFG_target}" "--device=$1" > /dev/null 
    return $?
}

list_lun() {
    declare OUTPUT=$("$HELPER" get-uuid "--cdir=$CFGDIR" "--target=${PMXCFG_target}" "--device=$1"|grep 'LUN UUID: ')
    [ $? -ne 0 ] && exit $?
    declare UUID=$(echo "$OUTPUT"|sed -e 's,^LUN UUID: ,,g')
    [ -z "$UUID" ] && exit 255
    echo $UUID
    return 0
}

list_view() {
    declare OUTPUT=$("$HELPER" get-lun "--cdir=$CFGDIR" "--target=${PMXCFG_target}" "--device=$1"|grep 'LUN: ')
    [ $? -ne 0 ] && exit $?
    declare LUN=$(echo "$OUTPUT"|sed -e 's,^LUN: ,,g')
    [ -z "$LUN" ] && exit 255
    echo $LUN
    return 0
}

case "$1" in
  create-lun) shift; create_lun $@;;
  delete-lun) shift; delete_lun $@;;
  list-lun) shift; list_lun $@;;
  list-view) shift; list_view $@;; 
  add-view)
	## Do nothing..
	;;
  *)
        ocf_log err "Invalid command: $COMMAND"
        #echo "Invalid command: $COMMAND" 1>&2
        exit 255
        ;;
esac

exit $?
