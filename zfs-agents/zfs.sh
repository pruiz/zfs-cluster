#!/bin/bash
#
# License:      GNU General Public License (GPL)
# Written by:   Pablo Ruiz <pablo.ruiz@gmail.com>
# Based on previous work by Saso Kiselkov.
#
#   This script manages ZFS pools
#   It can import a ZFS pool or export it
#
#   usage: $0 {start|stop|status|monitor|validate-all|meta-data}
#
#   The "start" arg imports a ZFS pool.
#   The "stop" arg exports it.
#
#       OCF parameters are as follows
#       OCF_RESKEY_pool - the pool to import/export
#
#   See: http://www.linux-ha.org/doc/dev-guides/ra-dev-guide.html
#
#######################################################################
# Initialization:

LC_ALL=C
LANG=C
PATH=/bin:/sbin:/usr/bin:/usr/sbin
export LC_ALL LANG PATH

if [ -f "$(dirname $0)/ocf-shellfuncs" ]
then \
    . $(dirname $0)/ocf-shellfuncs
    : ${HELPERS_DIR=$(dirname $0)/zfs.d}
else
    : ${OCF_FUNCTIONS_DIR=${OCF_ROOT}/lib/heartbeat}
    . ${OCF_FUNCTIONS_DIR}/ocf-shellfuncs
    : ${HELPERS_DIR=${OCF_ROOT}/lib/heartbeat/zfs.d}
fi

USAGE="usage: $0 {start|stop|status|monitor|validate-all|meta-data}";

#######################################################################

meta_data() {
        cat <<END
<?xml version="1.0"?>
<!DOCTYPE resource-agent SYSTEM "ra-api-1.dtd">
<resource-agent name="zfs">
<version>1.0</version>
<longdesc lang="en">
This script manages ZFS pools
It can import a ZFS pool or export it
</longdesc>
<shortdesc lang="en">Manages ZFS pools</shortdesc>

<parameters>
<parameter name="pool" unique="1" required="1" primary="1">
<longdesc lang="en">
The name of the ZFS pool to manage, e.g. "tank".
</longdesc>
<shortdesc lang="en">ZFS pool name</shortdesc>
<content type="string" default="" />
</parameter>
<parameter name="importargs" unique="0" required="0">
<longdesc lang="en">
Arguments to zpool import, e.g. "-d /dev/disk/by-id".
</longdesc>
<shortdesc lang="en">Import arguments</shortdesc>
<content type="string" default="" />
</parameter>
</parameters>

<actions>
<action name="start"   timeout="60s" />
<action name="stop"    timeout="60s" />
<action name="monitor" depth="0"  timeout="30s" interval="5s" />
<action name="validate-all"  timeout="30s" />
<action name="meta-data"  timeout="5s" />
</actions>
</resource-agent>
END
        exit $OCF_SUCCESS
}

zfs_helpers () {
    if [ -d "${HELPERS_DIR}" ]; then
        for helper in "${HELPERS_DIR}"/*.sh; do
            ocf_log debug "Invoking helper: ${helper} $@"
            CMDOUT="$(("${helper}" $@) 2>&1)"
            if [ "$?" -eq "0" ] ; then ocf_log debug "Helper done"
            else ocf_log err "Helper ${helper} failed: ${CMDOUT}"
            fi
        done
    fi
}

zpool_is_imported () {
    zpool list -H "$OCF_RESKEY_pool" > /dev/null
}

# Forcibly imports a ZFS pool, mounting all of its auto-mounted filesystems
# (as configured in the `mountpoint' and `canmount' properties)
# If the pool is already imported, no operation is taken.
# You can use the zfs-helper script to assist pool setup before and/or
# after import.
zpool_import () {
    declare pool="${OCF_RESKEY_pool}"
    declare importargs="$OCF_RESKEY_importargs"

    if ! zpool_is_imported; then
    ocf_log info "Importing ${pool}..."
    zfs_helpers pre-import "$pool"

        # The meanings of the options to import are as follows:
        #   -f : import even if the pool is marked as imported to another
        #        system - the system may have failed and not exported it
        #        cleanly.
        #   -o cachefile=none : the import should be temporary, so do not
        #        cache it persistently (across machine reboots). We want
        #        the CRM to explicitly control imports of this pool.
    CMDOUT="$((zpool import -f $importargs -o cachefile=none ${pool}) 2>&1)"
        if [ "$?" -eq "0" ] ; then
            ocf_log info "Successfully imported ${pool}."
        zfs_helpers post-import "$pool"
            return $OCF_SUCCESS
        else
            ocf_log err "Import of pool ${pool} failed: ${CMDOUT}"
            return $OCF_ERR_GENERIC
        fi
    else
        ocf_log info "Pool ${pool} was already imported."
    fi
}

# Forcibly exports a ZFS pool, unmounting all of its filesystems in the process
# If the pool is not imported, no operation is taken.
# You can use the zfs-helper script to assist pool setup before and/or
# after export.
zpool_export () {
    declare pool="${OCF_RESKEY_pool}"
    declare importargs="$OCF_RESKEY_importargs"

    if zpool_is_imported; then
        ocf_log debug "Exporting pool ${pool}.."
        zfs_helpers pre-export "$pool"

        # -f : force the export, even if we have mounted filesystems
        # Please note that this may fail with a "busy" error if there are
        # other kernel subsystems accessing the pool (e.g. SCSI targets).
        # Always make sure the pool export is last in your failover logic.
    CMDOUT="$((zpool export -f "${pool}") 2>&1)"
        if [ "$?" -eq "0" ] ; then
            ocf_log info "Successfully exported ${pool}."
            zfs_helpers post-export "$pool"
           return $OCF_SUCCESS
    else
            ocf_log err "Export of pool ${pool} failed: ${CMDOUT}"
            return $OCF_ERR_GENERIC
    fi
    else
        ocf_log info "Pool ${pool} was already exported."
    fi
}

# Monitors the health of a ZFS pool resource. Please note that this only
# checks whether the pool is imported and functional, not whether it has
# any degraded devices (use monitoring systems such as Zabbix for that).
zpool_monitor () {
    # If the pool is not imported, then we can't monitor its health
    if ! zpool_is_imported; then
        return $OCF_NOT_RUNNING
    fi

    # Check the pool status
    HEALTH=`zpool list -H -o health "$OCF_RESKEY_pool"`
    case "$HEALTH" in
        ONLINE|DEGRADED) return $OCF_SUCCESS;;
        FAULTED)         return $OCF_NOT_RUNNING;;
        *)               return $OCF_ERR_GENERIC;;
    esac
}

# Validates whether we can import a given ZFS pool
zpool_validate () {
    # Check that the `zpool' command is known
    if ! which zpool > /dev/null; then
        return $OCF_ERR_INSTALLED
    fi

    # If the pool is imported, then it is obviously valid
    if zpool_is_imported; then
        return $OCF_SUCCESS
    fi

    # Check that the pool can be imported
    if zpool import $OCF_RESKEY_importargs | grep 'pool:' | grep "\\<$OCF_RESKEY_pool\\>" > /dev/null;
    then
        return $OCF_SUCCESS
    else
        return $OCF_ERR_CONFIGURED
    fi
}

usage () {
    echo $USAGE >&2
    return $1
}

if [ $# -ne 1 ]; then
    usage $OCF_ERR_ARGS
fi

case $1 in
    meta-data)      meta_data;;
    start)          zpool_import;;
    stop)           zpool_export;;
    status|monitor) zpool_monitor;;
    validate-all)   zpool_validate;;
    usage)          usage $OCF_SUCCESS;;
    *)              usage $OCF_ERR_UNIMPLEMENTED;;
esac

exit $?

# vim: set smartindent expandtab ai ts=4 sw=4 :
