#!/usr/bin/env bash
# Creates an OSD and adds it to given Ceph deployment using ceph-deploy.
#
# Specially usefull when need to deploy an OSD over a LUKS device, given that
# ceph-volume deprecated the use of --dmcrypt parameter, thus ceph-deploy
# fails wonderfully when trying to use it, and the same happens when a mapper
# device is given. This script handles any block device by manually creating
# the LVM layer.
##############################################################################
#
#    create_osd.bash Copyright © 2018 HacKan (https://hackan.net)
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
##############################################################################

VERSION="0.2"

# /dev/mapper/cryptodisk
# /dev/sdX
BLOCK_DEVICE="$1"
VOLUME_GROUP="${2:-vg-$(cat /proc/sys/kernel/random/uuid)}"
LOGICAL_VOLUME="${3:-lv-$(cat /proc/sys/kernel/random/uuid)}"

bailout() {
	error "$*"
	exit 1
}

usage() {
	echo "$0 <block device> [<volume group name> [<logical volume name>]]"
	exit 1
}

info() {
	echo "[INFO   ] $*"
}

error() {
	echo "[ERROR  ] $*"
}

warning() {
	echo "[WARNING] $*"
}

info "CreateOSD v${VERSION} by HacKan | GNU GPL v3+"

[[ -z "$BLOCK_DEVICE" ]] && error "Block device is a mandatory parameter" && usage

[[ "$(whoami)" != "root" ]] && bailout "This script must be run as root"

info "Deploying at $(hostname)"
info "Zapping $BLOCK_DEVICE"
echo
ceph-volume lvm zap "$BLOCK_DEVICE" || bailout
echo
info "Creating LVM physical volume"
echo
pvcreate "$BLOCK_DEVICE" || bailout
echo
info "Creating LVM volume group $VOLUME_GROUP"
echo
vgcreate "$VOLUME_GROUP" "$BLOCK_DEVICE"
echo
info "Creating LVM logical volume $LOGICAL_VOLUME"
echo
lvcreate -l "100%FREE" -n "$LOGICAL_VOLUME" "$VOLUME_GROUP" || bailout
echo
ecode=1
if type ceph-deploy >/dev/null 2>&1 && [[ -f "./ceph.conf" && -f "./ceph.bootstrap-osd.keyring" ]]; then
	info "Running ceph-deploy to add device as OSD"
	echo
	ceph-deploy osd create --data "${VOLUME_GROUP}/${LOGICAL_VOLUME}" "$(hostname)"
	ecode=$?
else
	if type ceph-deploy >/dev/null 2>&1; then
		warning "I couldn't find ceph config nor keyring, you should run this script from the required ceph-deploy data directory"
	else
		warning "I couldn't find ceph-deploy executable"
	fi
	info "All is not lost, just run (at the right directory):"
	echo "ceph-deploy osd create --data ${VOLUME_GROUP}/${LOGICAL_VOLUME} $(hostname)"
	ecode=2
fi
echo
info "Finished"
exit $ecode
