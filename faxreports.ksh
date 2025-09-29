#!/bin/ksh

>/SCC-TMP/faxlog_not_normal.txt

for JOB_ID in $(vfxolog | grep -v NORMAL | grep -v SNDING | awk '{print $1}' | tail +2)
do
	printf "Parsing The Fax Server.....\n" >> /SCC-TMP/faxlog_not_normal.txt
	REQ=${JOB_ID}

	if [[ -z "$JOB_ID" ]]; then
		continue
	fi
	FAX_DEVICE=$(vfxolog -f atq ${REQ} 2>/dev/null | sed 's/"//g')
    
    if [[ -z "$FAX_DEVICE" ]]; then
        printf "ERROR: Could not find FAX_DEVICE for job ${REQ}. Skipping job.\n" >> /SCC-TMP/faxlog_not_normal.txt
        continue
    fi

	JOB_STATUS=$(vfxolog | grep -w ${REQ} 2>/dev/null | awk '{print $8}')
	FAX_TTY=$(vfxstat | grep -i ${FAX_DEVICE} 2>/dev/null | awk '{print $2}' | awk -F'-' '{print $1}')
    
    if [[ -z "$FAX_TTY" ]]; then
        printf "ERROR: Could not find FAX_TTY for device ${FAX_DEVICE}. Skipping job.\n" >> /SCC-TMP/faxlog_not_normal.txt
        continue
    fi
    
	DIGI_PARENT=$(lsdev -l ${FAX_TTY} -F parent 2>/dev/null)
	DIGI_PORT=$(lsdev | grep -w ${FAX_TTY} 2>/dev/null | awk '{print $3}' | awk -F'-' '{print $NF}')
    
    if [[ -z "$DIGI_PARENT" ]]; then
        printf "ERROR: Could not find DIGI_PARENT for TTY ${FAX_TTY}. Skipping job.\n" >> /SCC-TMP/faxlog_not_normal.txt
        DIGI_NAME="UNKNOWN"
        DIGI_IP="UNKNOWN"
    else
        DIGI_NAME=$(ps -ef | grep -- "-d/dev/$DIGI_PARENT" 2>/dev/null | grep -v grep | awk -F'-i' '{print $2}' | awk '{print $1}')
        DIGI_IP=$(grep -i ${DIGI_NAME} /etc/hosts 2>/dev/null | awk '{print $1}')
    fi
	
	printf "The fax job ${REQ} was sent via ${FAX_DEVICE} with a status of ${JOB_STATUS}. ${FAX_DEVICE} is associated with ${DIGI_NAME} on port ${DIGI_PORT}. ${DIGI_NAME}'s IP address is ${DIGI_IP}.\n" >> /SCC-TMP/faxlog_not_normal.txt
done

>/SCC-TMP/faxlog.txt
vfxolog | grep -v NORMAL | awk '{print $1}' > /SCC-TMP/faxlog.txt

mail -vs "Fax Report" marmar2401@icloud.com </SCC-TMP/faxlog_not_normal.txt
mail -vs "Fax Report" marmar2401@icloud.com</SCC-TMP/faxlog.txt
