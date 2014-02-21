#!/bin/bash
#
#
# 	iSCSITarget OCF RA. Exports and manages iSCSI targets.
#
#   (c) 2009-2010 Florian Haas, Dejan Muhamedagic, Pablo Ruiz García
#                 and Linux-HA contributors
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

#######################################################################
# Initialization:
LC_ALL=C
LANG=C
PATH=/bin:/sbin:/usr/bin:/usr/sbin
export LC_ALL LANG PATH

if [ -f "$(dirname $0)/ocf-shellfuncs" ]
then \
    . $(dirname $0)/ocf-shellfuncs
    . $(dirname $0)/utils/iscsi-lib.sh
    HA_RSCTMP=/var/run
else
    : ${OCF_FUNCTIONS_DIR=${OCF_ROOT}/lib/heartbeat}
    . ${OCF_FUNCTIONS_DIR}/ocf-shellfuncs
fi

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

# Listen on 0.0.0.0:3260 by default
OCF_RESKEY_portals_default="0.0.0.0:3260"
: ${OCF_RESKEY_portals=${OCF_RESKEY_portals_default}}

# Lockfile, used for selecting a target ID
LOCKFILE=${HA_RSCTMP}/iSCSITarget-${OCF_RESKEY_implementation}.lock
#######################################################################

meta_data() {
	cat <<END
<?xml version="1.0"?>
<!DOCTYPE resource-agent SYSTEM "ra-api-1.dtd">
<resource-agent name="iscsi-target" version="0.9">
<version>0.9</version>

<longdesc lang="en">
Manages iSCSI targets. An iSCSI target is a collection of SCSI Logical
Units (LUs) exported via a daemon that speaks the iSCSI protocol.
</longdesc>
<shortdesc lang="en">iSCSI target export agent</shortdesc>

<parameters>
<parameter name="implementation" required="0" unique="0">
<longdesc lang="en">
The iSCSI target daemon implementation. Must be one of "iet", "tgt",
or "lio".  If unspecified, an implementation is selected based on the
availability of management utilities, with "iet" being tried first,
then "tgt", then "lio".
</longdesc>
<shortdesc lang="en">Manages an iSCSI target export</shortdesc>
<content type="string" default="${OCF_RESKEY_implementation_default}"/>
</parameter>

<parameter name="iqn" required="1" unique="1" primary="1">
<longdesc lang="en">
The target iSCSI Qualified Name (IQN). Should follow the conventional
"iqn.yyyy-mm.&lt;reversed domain name&gt;[:identifier]" syntax.
</longdesc>
<shortdesc lang="en">iSCSI target IQN</shortdesc>
<content type="string" />
</parameter>

<parameter name="tid" required="0" unique="1">
<longdesc lang="en">
The iSCSI target ID. Required for tgt.
</longdesc>
<shortdesc lang="en">iSCSI target ID</shortdesc>
<content type="integer" />
</parameter>

<parameter name="portals" required="0" unique="0">
<longdesc lang="en">
iSCSI network portal addresses. Not supported by all
implementations. If unset, the default is to create one portal that
listens on ${OCF_RESKEY_portal_default}.
</longdesc>
<shortdesc lang="en">iSCSI portal addresses</shortdesc>
<content type="string" default="${OCF_RESKEY_portals_default}"/>
</parameter>

<parameter name="allowed_initiators" required="0" unique="0">
<longdesc lang="en">
Allowed initiators. A space-separated list of initiators allowed to
connect to this target. Initiators may be listed in any syntax
the target implementation allows. If this parameter is empty or
not set, access to this target will be allowed from any initiator.
</longdesc>
<shortdesc lang="en">List of iSCSI initiators allowed to connect
to this target</shortdesc>
<content type="string" default=""/>
</parameter>

<parameter name="incoming_username" required="0" unique="1">
<longdesc lang="en">
A username used for incoming initiator authentication. If unspecified,
allowed initiators will be able to log in without authentication.
This is a unique parameter, as it not allowed to re-use a single
username across multiple target instances.
</longdesc>
<shortdesc lang="en">Incoming account username</shortdesc>
<content type="string"/>
</parameter>

<parameter name="incoming_password" required="0" unique="0">
<longdesc lang="en">
A password used for incoming initiator authentication.
</longdesc>
<shortdesc lang="en">Incoming account password</shortdesc>
<content type="string"/>
</parameter>

<parameter name="additional_parameters" required="0" unique="0">
<longdesc lang="en">
Additional target parameters. A space-separated list of "name=value"
pairs which will be passed through to the iSCSI daemon's management
interface. The supported parameters are implementation
dependent. Neither the name nor the value may contain whitespace.
</longdesc>
<shortdesc lang="en">List of iSCSI target parameters</shortdesc>
<content type="string" />
</parameter>

</parameters>

<actions>
<action name="start"        timeout="10" />
<action name="stop"         timeout="10" />
<action name="status "      timeout="10" interval="10" depth="0" />
<action name="monitor"      timeout="10" interval="10" depth="0" />
<action name="meta-data"    timeout="5" />
<action name="validate-all"   timeout="10" />
</actions>
</resource-agent>
END
}

#######################################################################

iSCSITarget_usage() {
	cat <<END
usage: $0 {start|stop|status|monitor|validate-all|meta-data}

Expects to have a fully populated OCF RA-compliant environment set.
END
}

iSCSITarget_start() {
    iSCSITarget_monitor
    if [ $? =  $OCF_SUCCESS ]; then
	return $OCF_SUCCESS
    fi

    local param
    local name
    local value
    local initiator
    local portal

    case $OCF_RESKEY_implementation in
	iet)
	    local lasttid
	    local tid
	    if [ "${OCF_RESKEY_tid}" ]; then
		tid="${OCF_RESKEY_tid}"
	    else
    	        # Figure out the last used target ID, add 1 to get the new
	        # target ID.
		ocf_take_lock $LOCKFILE
		ocf_release_lock_on_exit $LOCKFILE
		lasttid=`sed -ne "s/tid:\([[:digit:]]\+\) name:.*/\1/p" < /proc/net/iet/volume | sort -n | tail -n1`
		[ -z "${lasttid}" ] && lasttid=0
		tid=$((++lasttid))
	    fi
	    # Create the target.
	    ocf_run ietadm --op new \
		--tid=${tid} \
		--params Name=${OCF_RESKEY_iqn} || exit $OCF_ERR_GENERIC
	    # Set additional parameters.
	    for param in ${OCF_RESKEY_additional_parameters}; do
		name=${param%=*}
		value=${param#*=}
		ocf_run ietadm --op update \
		    --tid=${tid} \
		    --params ${name}=${value} || exit $OCF_ERR_GENERIC
	    done
	    # Legacy versions of IET allow targets by default, current
	    # versions deny. To be safe we manage both the .allow and
	    # .deny files.
	    if [ -n "${OCF_RESKEY_allowed_initiators}" ]; then
		echo "${OCF_RESKEY_iqn} ALL" >> /etc/initiators.deny
		echo "${OCF_RESKEY_iqn} ${OCF_RESKEY_allowed_initiators// /,}" >> /etc/initiators.allow
	    else
		echo "${OCF_RESKEY_iqn} ALL" >> /etc/initiators.allow
	    fi
	    # In iet, adding a new user and assigning it to a target
	    # is one operation.
	    if [ -n "${OCF_RESKEY_incoming_username}" ]; then
		ocf_run ietadm --op new --user \
		    --tid=${tid} \
		    --params=IncomingUser=${OCF_RESKEY_incoming_username},Password=${OCF_RESKEY_incoming_password} \
		    || exit $OCF_ERR_GENERIC
	    fi
	    ;;
	tgt)
	    local tid
	    tid="${OCF_RESKEY_tid}"
	    # Create the target.
	    ocf_run tgtadm --lld iscsi --op new --mode target \
		--tid=${tid} \
		--targetname ${OCF_RESKEY_iqn} || exit $OCF_ERR_GENERIC
	    # Set parameters.
	    for param in ${OCF_RESKEY_additional_parameters}; do
		name=${param%=*}
		value=${param#*=}
		ocf_run tgtadm --lld iscsi --op update --mode target \
		    --tid=${tid} \
		    --name=${name} --value=${value} || exit $OCF_ERR_GENERIC
	    done
	    # For tgt, we always have to add access per initiator;
	    # access to targets is denied by default. If
	    # "allowed_initiators" is unset, we must use the special
	    # keyword ALL.
	    for initiator in ${OCF_RESKEY_allowed_initiators=ALL}; do
		ocf_run tgtadm --lld iscsi --op bind --mode target \
		    --tid=${tid} \
		    --initiator-address=${initiator} || exit $OCF_ERR_GENERIC
	    done
	    # In tgt, we must first create a user account, then assign
	    # it to a target using the "bind" operation.
	    if [ -n "${OCF_RESKEY_incoming_username}" ]; then
		ocf_run tgtadm --lld iscsi --mode account --op new \
		    --user=${OCF_RESKEY_incoming_username} \
		    --password=${OCF_RESKEY_incoming_password} || exit $OCF_ERR_GENERIC
		ocf_run tgtadm --lld iscsi --mode account --op bind \
		    --tid=${tid} \
		    --user=${OCF_RESKEY_incoming_username} || exit $OCF_ERR_GENERIC
	    fi
	    ;;
	lio)
	    # lio distinguishes between targets and target portal
	    # groups (TPGs). We will always create one TPG, with the
	    # number 1. In lio, creating a network portal
	    # automatically creates the corresponding target if it
	    # doesn't already exist.
	    for portal in ${OCF_RESKEY_portals}; do
		ocf_run lio_node --addnp ${OCF_RESKEY_iqn} 1 \
		    ${portal} || exit $OCF_ERR_GENERIC
	    done
	    # in lio, we can set target parameters by manipulating
	    # the appropriate configfs entries
	    for param in ${OCF_RESKEY_additional_parameters}; do
		name=${param%=*}
		value=${param#*=}
		configfs_path="/sys/kernel/config/target/iscsi/${OCF_RESKEY_iqn}/tpgt_1/param/${name}"
		if [ -e ${configfs_path} ]; then
		    echo ${value} > ${configfs_path} || exit $OCF_ERR_GENERIC
		else
		    ocf_log warn "Unsupported iSCSI target parameter ${name}: will be ignored."
		fi
	    done
	    # lio does per-initiator filtering by default. To disable
	    # this, we need to switch the target to "permissive mode".
	    if [ -n "${OCF_RESKEY_allowed_initiators}" ]; then
		for initiator in ${OCF_RESKEY_allowed_initiators}; do
		    ocf_run lio_node --addnodeacl ${OCF_RESKEY_iqn} 1 \
			${initiator} || exit $OCF_ERR_GENERIC
		done
	    else
		ocf_run lio_node --permissive ${OCF_RESKEY_iqn} 1 || exit $OCF_ERR_GENERIC
		# permissive mode enables read-only access by default,
		# so we need to change that to RW to be in line with
		# the other implementations.
		echo 0 > "/sys/kernel/config/target/iscsi/${OCF_RESKEY_iqn}/tpgt_1/attrib/demo_mode_write_protect"
		if [ `cat /sys/kernel/config/target/iscsi/${OCF_RESKEY_iqn}/tpgt_1/attrib/demo_mode_write_protect` -ne 0 ]; then
		    ocf_log err "Failed to disable write protection for target ${OCF_RESKEY_iqn}."
		    exit $OCF_ERR_GENERIC
		fi
	    fi
	    # TODO: add CHAP authentication support when it gets added
	    # back into LIO
	    ocf_run lio_node --disableauth ${OCF_RESKEY_iqn} 1 || exit $OCF_ERR_GENERIC
	    # Finally, we need to enable the target to allow
	    # initiators to connect
	    ocf_run lio_node --enabletpg=${OCF_RESKEY_iqn} 1 || exit $OCF_ERR_GENERIC
	    ;;
    esac

    return $OCF_SUCCESS
}

iSCSITarget_stop() {
    iSCSITarget_monitor
    if [ $? =  $OCF_SUCCESS ]; then
	local tid
	case $OCF_RESKEY_implementation in
	    iet)
		# Figure out the target ID
		tid=`sed -ne "s/tid:\([[:digit:]]\+\) name:${OCF_RESKEY_iqn}/\1/p" < /proc/net/iet/volume`
		if [ -z "${tid}" ]; then
		    ocf_log err "Failed to retrieve target ID for IQN ${OCF_RESKEY_iqn}"
		    exit $OCF_ERR_GENERIC
		fi
		# Close existing connections. There is no other way to
		# do this in IET than to parse the contents of
		# /proc/net/iet/session.
		set -- $(sed -ne '/^tid:'${tid}' /,/^tid/ {
                          /^[[:space:]]*sid:\([0-9]\+\)/ {
                             s/^[[:space:]]*sid:\([0-9]*\).*/--sid=\1/; h;
                          };
                          /^[[:space:]]*cid:\([0-9]\+\)/ { 
                              s/^[[:space:]]*cid:\([0-9]*\).*/--cid=\1/; G; p; 
                          }; 
                      }' < /proc/net/iet/session)
		while [[ -n $2 ]]; do
                    # $2 $1 looks like "--sid=X --cid=Y"
		    ocf_run ietadm --op delete \
			     --tid=${tid} $2 $1
		    shift 2
		done
   	        # In iet, unassigning a user from a target and
		# deleting the user account is one operation.
		if [ -n "${OCF_RESKEY_incoming_username}" ]; then
		    ocf_run ietadm --op delete --user \
			--tid=${tid} \
			--params=IncomingUser=${OCF_RESKEY_incoming_username} \
			|| exit $OCF_ERR_GENERIC
		fi
		# Loop on delete. Keep trying until we time out, if
		# necessary.
		while true; do
		    if ietadm --op delete --tid=${tid}; then
			ocf_log debug "Removed target ${OCF_RESKEY_iqn}."
			break
		    else
			ocf_log warn "Failed to remove target ${OCF_RESKEY_iqn}, retrying."
			sleep 1
		    fi
		done
		# Avoid stale /etc/initiators.{allow,deny} entries
		# for this target
		if [ -e /etc/initiators.deny ]; then
		    ocf_run sed -e "/^${OCF_RESKEY_iqn}[[:space:]]/d" \
			-i /etc/initiators.deny
		fi
		if [ -e /etc/initiators.allow ]; then
		    ocf_run sed -e "/^${OCF_RESKEY_iqn}[[:space:]]/d" \
			-i /etc/initiators.allow
		fi
		;;
	    tgt)
		tid="${OCF_RESKEY_tid}"
		# Close existing connections. There is no other way to
		# do this in tgt than to parse the output of "tgtadm --op
		# show".
		set -- $(tgtadm --lld iscsi --op show --mode target \
		    | sed -ne '/^Target '${tid}':/,/^Target/ {
                          /^[[:space:]]*I_T nexus: \([0-9]\+\)/ {
                             s/^.*: \([0-9]*\).*/--sid=\1/; h;
                          };
                          /^[[:space:]]*Connection: \([0-9]\+\)/ { 
                              s/^.*: \([0-9]*\).*/--cid=\1/; G; p; 
                          }; 
                          /^[[:space:]]*LUN information:/ q; 
                      }')
		while [[ -n $2 ]]; do
                    # $2 $1 looks like "--sid=X --cid=Y"
		    ocf_run tgtadm --lld iscsi --op delete --mode connection \
			--tid=${tid} $2 $1
		    shift 2
		done
	        # In tgt, we must first unbind the user account from
		# the target, then remove the account itself.
		if [ -n "${OCF_RESKEY_incoming_username}" ]; then
		    ocf_run tgtadm --lld iscsi --mode account --op unbind \
			--tid=${tid} \
			--user=${OCF_RESKEY_incoming_username} || exit $OCF_ERR_GENERIC
		    ocf_run tgtadm --lld iscsi --mode account --op delete \
			--user=${OCF_RESKEY_incoming_username} || exit $OCF_ERR_GENERIC
		fi
		# Loop on delete. Keep trying until we time out, if
		# necessary.
		while true; do
		    if tgtadm --lld iscsi --op delete --mode target --tid=${tid}; then
			ocf_log debug "Removed target ${OCF_RESKEY_iqn}."
			break
		    else
			ocf_log warn "Failed to remove target ${OCF_RESKEY_iqn}, retrying."
			sleep 1
		    fi
		done
		# In tgt, we don't have to worry about our ACL
		# entries. They are automatically removed upon target
		# deletion.
		;;
	    lio)
		# In lio, removing a target automatically removes all
		# associated TPGs, network portals, and LUNs.
		ocf_run lio_node --deliqn ${OCF_RESKEY_iqn} || exit $OCF_ERR_GENERIC
		;;
	esac
    fi

    return $OCF_SUCCESS
}

iSCSITarget_monitor() {
    case $OCF_RESKEY_implementation in
	iet)
	    grep -Eq "tid:[0-9]+ name:${OCF_RESKEY_iqn}" /proc/net/iet/volume && return $OCF_SUCCESS
	    ;;
	tgt)
	    tgtadm --lld iscsi --op show --mode target \
		| grep -Eq "Target [0-9]+: ${OCF_RESKEY_iqn}" && return $OCF_SUCCESS
	    ;;
	lio)
	    # if we have no configfs entry for the target, it's
	    # definitely stopped
	    [ -d /sys/kernel/config/target/iscsi/${OCF_RESKEY_iqn} ] || return $OCF_NOT_RUNNING
	    # if the target is there, but its TPG is not enabled, then
	    # we also consider it stopped
	    [ `cat /sys/kernel/config/target/iscsi/${OCF_RESKEY_iqn}/tpgt_1/enable` -eq 1 ] || return $OCF_NOT_RUNNING
	    return $OCF_SUCCESS
	    ;;
    esac
    
    return $OCF_NOT_RUNNING
}

iSCSITarget_validate() {
    # Do we have all required variables?
    local required_vars
    case $OCF_RESKEY_implementation in
	iet)
	    required_vars="implementation iqn"
	    ;;
	tgt)
	    required_vars="implementation iqn tid"
	    ;;
    esac
    for var in ${required_vars}; do
	param="OCF_RESKEY_${var}"
	if [ -z "${!param}" ]; then
	    ocf_log error "Missing resource parameter \"$var\"!"
	    exit $OCF_ERR_CONFIGURED
	fi
    done

    # Is the configured implementation supported?
    case $OCF_RESKEY_implementation in
	iet|tgt|lio)
	    ;;
	*)
	    ocf_log error "Unsupported iSCSI target implementation \"$OCF_RESKEY_implementation\"!"
	    exit $OCF_ERR_CONFIGURED
    esac

    # Do we have any configuration parameters that the current
    # implementation does not support?
    local unsupported_params
    local var
    local envar
    case $OCF_RESKEY_implementation in
	iet|tgt)
	    # IET and tgt do not support binding a target portal to a
	    # specific IP address.
	    unsupported_params="portals"
	    ;;
	lio)
	    # TODO: Remove incoming_username and incoming_password
	    # from this check when LIO 3.0 gets CHAP authentication
	    unsupported_params="tid incoming_username incoming_password"
	    ;;
    esac
    for var in ${unsupported_params}; do
	envar=OCF_RESKEY_${var}
	if [ -n "${!envar}" ]; then
	    ocf_log warn "Configuration parameter \"${var}\"" \
		"is not supported by the iSCSI implementation" \
		"and will be ignored."
	fi
    done

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
	    lio)
	        # lio needs configfs to be mounted
		if ! grep -Eq "^.*/sys/kernel/config[[:space:]]+configfs" /proc/mounts; then
		    ocf_log err "configfs not mounted at /sys/kernel/config -- check if required modules are loaded."
		    exit $OCF_ERR_INSTALLED
		fi
	        # check for configfs entries created by target_core_mod
		if [ ! -d /sys/kernel/config/target ]; then
		    ocf_log err "/sys/kernel/config/target does not exist or is not a directory -- check if required modules are loaded."
		    exit $OCF_ERR_INSTALLED
		fi
		;;
	esac
    fi

    return $OCF_SUCCESS
}


case $1 in
  meta-data)
	meta_data
	exit $OCF_SUCCESS
	;;
  usage|help)
	iSCSITarget_usage
	exit $OCF_SUCCESS
	;;
esac

# Everything except usage and meta-data must pass the validate test
iSCSITarget_validate

case $__OCF_ACTION in
start)		iSCSITarget_start;;
stop)		iSCSITarget_stop;;
monitor|status)	iSCSITarget_monitor;;
reload)		ocf_log err "Reloading..."
	        iSCSITarget_start
		;;
validate-all)	;;
*)		iSCSITarget_usage
		exit $OCF_ERR_UNIMPLEMENTED
		;;
esac
rc=$?
ocf_log debug "${OCF_RESOURCE_INSTANCE} $__OCF_ACTION : $rc"
exit $rc