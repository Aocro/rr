#!/usr/bin/env bash
#
# Copyright (C) 2022 Ing <https://github.com/wjz304>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

PROMPT=$(sudo -nv 2>&1)
if [ $? -ne 0 ]; then
  echo "This script must be run as root"
  exit 1
fi

REPO="https://github.com/RROrg/rr"
PRERELEASE="true"
TAG=""
if [ "${PRERELEASE}" = "true" ]; then
  TAG="$(curl -skL "${REPO}/tags" | grep /refs/tags/.*\.zip  | sed -r 's/.*\/refs\/tags\/(.*)\.zip.*$/\1/' | sort -rV | head -1)"
else
  LATESTURL="$(curl -skL --connect-timeout 10 -w %{url_effective} -o /dev/null "${REPO}/releases/latest")"
  TAG="${LATESTURL##*/}"
fi
[ "${TAG:0:1}" = "v" ] && TAG="${TAG:1}"

rm -rf "/tmp/rr-${TAG}.img.zip" "/tmp/rr.img"
STATUS=$(curl -kL -w "%{http_code}" "${REPO}/releases/download/${TAG}/rr-${TAG}.img.zip" -o "/tmp/rr-${TAG}.img.zip")
if [ $? -ne 0 -o ${STATUS:-0} -ne 200 ]; then
  echo "Download failed"
  exit 1
fi

unzip "/tmp/rr-${TAG}.img.zip" -d "/tmp/"

LOOPX=$(sudo losetup -f)
sudo losetup -P "${LOOPX}" "/tmp/rr.img"

rm -rf "/tmp/mnt/p3"
mkdir -p "/tmp/mnt/p3"
sudo mount ${LOOPX}p3 "/tmp/mnt/p3" || (
  echo -e "Can't mount ${LOOPX}p3."
  exit 1
)
cp -rf "/tmp/mnt/p3/modules" "/tmp/upmodules"
sudo umount "/tmp/mnt/p3"
rm -rf "/tmp/mnt/p3"
sudo losetup --detach ${LOOPX}
rm -rf "/tmp/rr-${TAG}.img.zip" "/tmp/rr.img"

MODULES=""
MODULES+="{"
for F in /tmp/upmodules/*.tgz; do
  echo "${F}"
  mkdir -p "${F%.tgz}"
  tar -zxf "${F}" -C "${F%.tgz}" && rm -f "${F}" || echo "Failed to extract ${F}"
  MODULES+="\"$(basename "${F}" .tgz)\":{"
  for M in $(find "${F%.tgz}" -name \*.ko); do
    MODULES+="\"$(basename "${M}" .ko)\": {\"description\": \"$(echo $(/sbin/modinfo "${M}" | grep '^description' | cut -d: -f2))\"},"
  done
  [ "${MODULES: -1}" = "," ] && MODULES="${MODULES%?}"
  MODULES+="},"
done
[ "${MODULES: -1}" = "," ] && MODULES="${MODULES%?}"
MODULES+="}"
echo "${MODULES}" | jq '.' >/tmp/upmodules/modules.json

sudo cp -f /www/wwwroot/mi-d.cn/d/modules/busybox /www/wwwroot/mi-d.cn/d/modules/jq /www/wwwroot/mi-d.cn/d/modules/*.sh /tmp/upmodules
sudo mv -f /www/wwwroot/mi-d.cn/d/modules /www/wwwroot/mi-d.cn/d/modules.$(date +%s)
sudo mv -f /tmp/upmodules /www/wwwroot/mi-d.cn/d/modules
