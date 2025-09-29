#!/bin/ksh

printf "Parsing The Fax Server.....\n"

REQ=$1

# FIXED: Added closing parenthesis ')'
FAX_DEVICE=$(vfxolog -f atq ${REQ} | sed 's/"//g')

JOB_STATUS=$(vfxolog | grep -i ${REQ} | awk '{print $8}')

# FIXED: Added closing parenthesis ')'
FAX_TTY=$(vfxstat | grep -i ${FAX_DEVICE} | awk '{print $2}' | awk -F'-' '{print $1}')

DIGI_PARENT=$(lsdev -l ${FAX_TTY} -F parent )

DIGI_PORT=$(lsdev | grep -w ${FAX_TTY} | awk '{print $3}' | awk -F'-' '{print $NF}')

# Added grep -v grep for better reliability on AIX
DIGI_NAME=$(ps -ef | grep -- "-d/dev/$DIGI_PARENT" | grep -v grep | awk -F'-i' '{print $2}' | awk '{print $1}')

DIGI_IP=$(grep -i ${DIGI_NAME} /etc/hosts | awk '{print $1}')

printf "The fax job ${REQ} was sent via ${FAX_DEVICE} with a status of ${JOB_STATUS}. ${FAX_DEVICE} is associated with ${DIGI_NAME} on port ${DIGI_PORT}. ${DIGI_NAME}'s IP address is ${DIGI_IP}.\n"
