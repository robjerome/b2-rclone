#!/bin/sh -e

RCLONE="/usr/bin/rclone"

B2_ROOT=$(cd `dirname "${0}"` && pwd)
B2_PARM="${B2_ROOT}/backup.b2"

param()
{
  eval ${3}=$(cat "${1}" | grep -E "^${2}=" | sed "s|^${2}=||")
}

param "${B2_PARM}" "PASSPHRASE" B2_MAGIC
param "${B2_PARM}" "BUCKET"     B2_BUCKET
param "${B2_PARM}" "KEYID"      B2_KEYID
param "${B2_PARM}" "APPKEY"     B2_APPKEY

B2_LIST="${B2_ROOT}/.sync"
B2_SYNC="${B2_ROOT}/sync"

RCLONE_CONF="${B2_ROOT}/rclone.conf"

echo "[remote]"              >  "${RCLONE_CONF}"
echo "type = b2"             >> "${RCLONE_CONF}"
echo "account = ${B2_KEYID}" >> "${RCLONE_CONF}"
echo "key = ${B2_APPKEY}"    >> "${RCLONE_CONF}"
echo "hard_delete = true"    >> "${RCLONE_CONF}"

RCLONE_FLAGS="--config ${RCLONE_CONF} --log-level INFO --bwlimit 512K"

rm -rf ${B2_SYNC} && mkdir -p "${B2_SYNC}" && rm -f "${B2_LIST}" && touch "${B2_LIST}"

while IFS= read -r LINE ; do
  if [ -f "${LINE}" ] ; then
    echo "${LINE}" >> "${B2_LIST}"
  elif [ -d "${LINE}" ]; then
    find "${LINE}" -type f >> "${B2_LIST}"
  fi
done < $(echo ${0} | sed "s|\.sh$|.in|")

sed "s|^/||" -i "${B2_LIST}"

if [ $(cat "${B2_LIST}" | wc -l) -ne 0 ] ; then
  printf "\nEncrypting ...\n\n"
fi

while IFS= read -r LINE ; do
  echo "/${LINE}"
  mkdir -p "${B2_SYNC}/$(dirname "${LINE}")"
  openssl enc -e -aes256 -iter 1 -nosalt -pass "pass:${B2_MAGIC}" -in "/${LINE}" -out "${B2_SYNC}/${LINE}"
  touch -r "/${LINE}" "${B2_SYNC}/${LINE}"
done < "${B2_LIST}"

printf "\nSyncing ...\n\n"

"${RCLONE}" ${RCLONE_FLAGS} sync --checksum "${B2_SYNC}" "remote:${B2_BUCKET}"
"${RCLONE}" ${RCLONE_FLAGS} cleanup "remote:${B2_BUCKET}"
"${RCLONE}" ${RCLONE_FLAGS} --b2-versions ls "remote:${B2_BUCKET}" | awk '{print $2}' > "${B2_LIST}"

rm "${RCLONE_CONF}"

printf "Done.\n\n"
