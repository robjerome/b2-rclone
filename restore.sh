#!/bin/sh -e

RCLONE="/usr/bin/rclone"
OPENSSL="/usr/bin/openssl"

B2_ROOT=$(cd `dirname "${0}"` && pwd)
B2_PARM="${B2_ROOT}/backup.b2"

param()
{
  eval ${3}=$(cat "${1}" | grep -E "^${2}=" | sed "s|^${2}=||")
}

param "${B2_PARM}" "PASSPHRASE"  B2_MAGIC
param "${B2_PARM}" "BUCKET"      B2_BUCKET
param "${B2_PARM}" "KEYID"       B2_KEYID
param "${B2_PARM}" "APPKEY"      B2_APPKEY
param "${B2_PARM}" "DIRECTORY"   B2_DIRECTORY

B2_SYNC_DIR="${B2_DIRECTORY:-$B2_ROOT}/sync"
B2_SYNC_LST="${B2_ROOT}/.sync"

B2_REST_DIR="${B2_DIRECTORY:-$B2_ROOT}/restore"
B2_REST_LST="${B2_ROOT}/.restore"

mkdir -p "${B2_SYNC_DIR}" && rm -f "${B2_SYNC_LST}" && touch "${B2_SYNC_LST}" && rm -f "${B2_REST_LST}"

RCLONE_CONF="${B2_ROOT}/rclone.conf"

echo "[remote]"              >  "${RCLONE_CONF}"
echo "type = b2"             >> "${RCLONE_CONF}"
echo "account = ${B2_KEYID}" >> "${RCLONE_CONF}"
echo "key = ${B2_APPKEY}"    >> "${RCLONE_CONF}"
echo "hard_delete = true"    >> "${RCLONE_CONF}"

RCLONE_FLAGS="--config ${RCLONE_CONF} --bwlimit 2M --log-level INFO --stats-one-line --stats 5m"

if [ $# -eq 0 ] ; then
  printf "\nListing ...\n\n"
  "${RCLONE}" ${RCLONE_FLAGS} --b2-versions ls "remote:${B2_BUCKET}"
  printf "\nSpecify the file to restore or --full to restore everthing\n"
elif [ $# -eq 1 ] && [ "${1}" = "--full" ] ; then
  printf "\nSyncing ...\n\n"
  "${RCLONE}" ${RCLONE_FLAGS} --b2-versions ls "remote:${B2_BUCKET}" | awk '{for(i=2;i<NF;i++) printf $i " "; print $NF}' > "${B2_SYNC_LST}"
  "${RCLONE}" ${RCLONE_FLAGS} sync --checksum "remote:${B2_BUCKET}" "${B2_SYNC_DIR}"
else
  printf "\nSyncing ...\n\n"
  "${RCLONE}" ${RCLONE_FLAGS} --b2-versions ls "remote:${B2_BUCKET}" | awk '{for(i=2;i<NF;i++) printf $i " "; print $NF}' > "${B2_REST_LST}"
  for OBJECT in "$@" ; do
    OBJECT=$(echo "${OBJECT}" | sed "s|/$||")
    FILE=$(grep -E "^${OBJECT}$" "${B2_REST_LST}" | tee -a "${B2_SYNC_LST}")
    if [ "${FILE}" != "" ] ; then
      printf "\n[file] ${OBJECT}\n\n"
      "${RCLONE}" ${RCLONE_FLAGS} sync --checksum "remote:${B2_BUCKET}/${OBJECT}" "${B2_SYNC_DIR}/$(dirname "${FILE}")"
    else
      DIRECTORY=$(grep -E "^${OBJECT}" "${B2_REST_LST}" | tee -a "${B2_SYNC_LST}")
      if [ "${DIRECTORY}" != "" ] ; then
        printf "\n[directory] ${OBJECT}\n\n"
        "${RCLONE}" ${RCLONE_FLAGS} sync --checksum "remote:${B2_BUCKET}/${OBJECT}" "${B2_SYNC_DIR}/${OBJECT}"
      fi
    fi
  done
  rm -f "${B2_REST_LST}"
fi

sed "s|^/||" -i "${B2_SYNC_LST}"

if [ $(cat "${B2_SYNC_LST}" | wc -l) -ne 0 ] ; then
  printf "Decrypting ...\n\n"
fi

while IFS= read -r LINE ; do
   echo "${B2_REST_DIR}/${LINE}"
   mkdir -p "$(dirname "${B2_REST_DIR}/${LINE}")"
   "${OPENSSL}" enc -d -aes256 -iter 1 -nosalt -pass "pass:${B2_MAGIC}" -in "${B2_SYNC_DIR}/${LINE}" -out "${B2_REST_DIR}/${LINE}"
done < "${B2_SYNC_LST}"

rm "${RCLONE_CONF}"

printf "\nDone.\n\n"
