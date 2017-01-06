#!/bin/bash
#
#
#   iSCSI (Multiple) LogicalUnits OCF RA. Exports and manages iSCSI LUNs
#
#   (c) 2014 Pablo Ruiz Garcia
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of version 2 of the GNU General Public License as
# published by the Free Software Foundation.
#
# This program is distributed in the hope that it would be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
#
# Further, this software is distributed without any warranty that it is
# free of the rightful claim of any third person regarding infringement
# or the like.  Any license provided herein, whether implied or
# otherwise, applies only to this software file.  Patent licenses, if
# any, provided herein do not apply to combinations of this program with
# other software, or any other product whatsoever.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write the Free Software Foundation,
# Inc., 59 Temple Place - Suite 330, Boston MA 02111-1307, USA.
#

# Modified in order to work with zfs-agents by <pablo.ruiz@gmail.com>

#######################################################################
# Initialization:
LC_ALL=C
LANG=C
PATH=/bin:/sbin:/usr/bin:/usr/sbin
export LC_ALL LANG PATH

: ${OCF_FUNCTIONS_DIR=${OCF_ROOT}/lib/heartbeat}
. ${OCF_FUNCTIONS_DIR}/ocf-shellfuncs
: ${THIS_FUNCTIONS_DIR=${OCF_ROOT}/lib/netway}
. ${THIS_FUNCTIONS_DIR}/iscsi-lib.sh

HA_RSCTMP=/var/run

# Defaults
# Set a default implementation based on software installed
if have_binary ietadm; then
    OCF_RESKEY_implementation_default="iet"
elif have_binary tgtadm; then
    OCF_RESKEY_implementation_default="tgt"
elif have_binary lio_node; then
    OCF_RESKEY_implementation_default="lio"
fi
: ${OCF_RESKEY_implementation=${OCF_RESKEY_implementation_default}}

meta_data() {
	cat <<END
<?xml version="1.0"?>
<!DOCTYPE resource-agent SYSTEM "ra-api-1.dtd">
<resource-agent name="iscsi-luns" version="0.9">
<version>0.9</version>

<longdesc lang="en">
Manages (multiple) iSCSI Logical Units from an independent settings file
per each LUN so we can add/remove LUNs dinamically w/o changing cluster config.
An iSCSI Logical unit is a subdivision of an SCSI Target, exported 
via a daemon that speaks the iSCSI protocol.
</longdesc>
<shortdesc lang="en">Manages iSCSI Logical Units (LUs)</shortdesc>

<parameters>
<parameter name="configpath" required="1" unique="1" primary="1">
<longdesc lang="en">
Path to LUNs' configuration file's directory. This should be a folder shared
by all cluster nodes, so each newly added/deleted LUN can be accessed by 
the promoted node after a failover.
</longdesc>
<shortdesc lang="en">Path to LUNs' configuration file's directory</shortdesc>
<content type="string" />
</parameter>

<parameter name="implementation" required="0" unique="0">
<longdesc lang="en">
The iSCSI target daemon implementation. Must be one of "iet", "tgt",
or "lio".  If unspecified, an implementation is selected based on the
availability of management utilities, with "iet" being tried first,
then "tgt", then "lio".
</longdesc>
<shortdesc lang="en">iSCSI target daemon implementation</shortdesc>
<content type="string" default="${OCF_RESKEY_implementation_default}"/>
</parameter>

<parameter name="iqn" unique="0" inherit="iqn">
<longdesc lang="en">
The iSCSI Qualified Name (IQN) that this Logical Unit belongs to.
</longdesc>
<shortdesc lang="en">iSCSI target IQN</shortdesc>
<content type="string" />
</parameter>

</parameters>

<actions>
<action name="start"        timeout="10" />
<action name="stop"         timeout="10" />
<action name="status"       timeout="10" interval="10" depth="0" />
<action name="monitor"      timeout="10" interval="10" depth="0" />
<action name="meta-data"    timeout="5" />
<action name="validate-all"   timeout="10" />
</actions>

<special tag="rgmanager">
<child type="iscsi-targets" forbid="1"/>
<child type="iscsi-lun" forbid="1"/>
<child type="iscsi-luns" forbid="1"/>
<child type="ip" start="2" stop="1"/>
</special>

</resource-agent>
END
}

#######################################################################

iSCSILogicalUnits_start() {
    declare CONFIGPATH="$OCF_RESKEY_configpath"
    declare target="$OCF_RESKEY_iqn"
    declare engine="$OCF_RESKEY_implementation"

    ocf_log debug "Starting iSCSI LUNs for: ${target}"
   
    declare tid=$(iscsi_get_tid "${engine}" "${target}")
    declare dir="${CONFIGPATH}/${target}"

    if [ ! -d "$dir" -o -z "$(ls ${dir})" ]; then
        ocf_log debug "No luns defined for target: ${target}"
        exit $OCF_SUCCESS
    fi

    for file in ${dir}/*
    do \
        iscsi_lun_status "${file}" "${engine}" "${target}"; rc=$?
        if [ $rc -eq $OCF_NOT_RUNNING ]; then
            iscsi_start_lun "${file}" "${engine}" "${target}"; rc=$?
        fi
        [ $rc -ne $OCF_SUCCESS ] && return $rc
    done

    return $OCF_SUCCESS
}

iSCSILogicalUnits_stop() {
    declare CONFIGPATH="$OCF_RESKEY_configpath"
    declare target="$OCF_RESKEY_iqn"
    declare engine="$OCF_RESKEY_implementation"
    declare ret=$OCF_SUCCESS
    declare rc=$OCF_SUCCESS

    ocf_log debug "Stopping iSCSI LUNs for: ${target}"
   
    declare tid=$(iscsi_get_tid "${engine}" "${target}")
    declare dir="${CONFIGPATH}/${target}"

    if [ ! -d "$dir" -o -z "$(ls ${dir})" ]; then
        ocf_log debug "No luns defined for target: ${target}"
        exit $OCF_SUCCESS
    fi

    for file in ${dir}/*
    do \
        iscsi_lun_status "${file}" "${engine}" "${target}"; rc=$?
        if [ $rc -eq $OCF_SUCCESS ]; then
            iscsi_stop_lun "${file}" "${engine}" "${target}"; rc=$?
        fi
        [ $rc -ne $OCF_SUCCESS ] && ret=$rc
    done

    return $ret
}

iSCSILogicalUnits_monitor() {
    declare CONFIGPATH="$OCF_RESKEY_configpath"
    declare target="$OCF_RESKEY_iqn"
    declare engine="$OCF_RESKEY_implementation"
    declare ret=$OCF_SUCCESS

    ocf_log debug "Monitoring iSCSI LUNs for: ${target}"
   
    declare tid=$(iscsi_get_tid "${engine}" "${target}")
    declare dir="${CONFIGPATH}/${target}"

    if [ ! -d "$dir" -o -z "$(ls ${dir})" ]; then
        ocf_log debug "No luns defined for target: ${target}"
        exit $OCF_SUCCESS
    fi

    for file in ${dir}/*
    do \
        iscsi_lun_status "${file}" "${engine}" "${target}"; ret=$?
        [ $ret -ne $OCF_SUCCESS ] && return $ret
    done

    return $OCF_SUCCESS
}

iSCSILogicalUnits_validate() {
    # Do we have all required variables?
    for var in configpath implementation iqn; do
	param="OCF_RESKEY_${var}"
	if [ -z "${!param}" ]; then
	    ocf_log error "Missing resource parameter \"$var\"!"
	    exit $OCF_ERR_CONFIGURED
	fi
    done

    if [ ! -d "$OCF_RESKEY_configpath" ]; then
        ocf_log error "Config file does not exists or is not a directory!"
        exit $OCF_ERR_CONFIGURED
    fi

    # Is the configured implementation supported?
    case $OCF_RESKEY_implementation in
	iet|tgt|lio)
	    ;;
	*)
	    ocf_log error "Unsupported iSCSI target implementation \"$OCF_RESKEY_implementation\"!"
	    exit $OCF_ERR_CONFIGURED
    esac

    if ! ocf_is_probe; then
    # Do we have all required binaries?
	case $OCF_RESKEY_implementation in
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
	case $OCF_RESKEY_implementation in
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

iSCSILogicalUnits_usage() {
	cat <<END
usage: $0 {start|stop|status|monitor|validate-all|meta-data}

Expects to have a fully populated OCF RA-compliant environment set.
END
}

case $1 in
  meta-data)
	meta_data
	exit $OCF_SUCCESS
	;;
  usage|help)
	iSCSILogicalUnits_usage
	exit $OCF_SUCCESS
	;;
esac

# Everything except usage and meta-data must pass the validate test
iSCSILogicalUnits_validate

case $__OCF_ACTION in
start)		iSCSILogicalUnits_start;;
stop)		iSCSILogicalUnits_stop;;
monitor|status)	iSCSILogicalUnits_monitor;;
reload)		ocf_log err "Reloading..."
	        iSCSILogicalUnits_start
		;;
validate-all)	;;
*)		iSCSILogicalUnits_usage
		exit $OCF_ERR_UNIMPLEMENTED
		;;
esac
rc=$?
ocf_log debug "${OCF_RESOURCE_INSTANCE} $__OCF_ACTION : $rc"
exit $rc
