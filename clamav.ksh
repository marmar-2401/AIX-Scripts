#!/bin/ksh
# =============================================================================
#  clamav.ksh — ClamAV Installation and Management for AIX
#  Author: Mark Pierce-Zellfrow
#  AIX Edition — Korn Shell (AIX 7.1 / 7.2 / 7.3)
# =============================================================================

# ── Colors ────────────────────────────────────────────────────────────────────
BLACK='\033[0;30m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[0;37m'
NC='\033[0m'

# ── Constants ─────────────────────────────────────────────────────────────────
STAGING_DIR="/SCC-TMP"
CLAM_STAGING="${STAGING_DIR}/clamaix"
TAR_FILE="clamaix.tar"
LIBUNWIND_BFF="${CLAM_STAGING}/libunwind.17.1.3.0.bff"
CLAMAV_RPM="${CLAM_STAGING}/clamav-1.4.3-1.aix7.2.ppc.rpm"
FRESHCLAM_CONF_SRC="${CLAM_STAGING}/freshclam.conf"
FRESHCLAM_CONF_DEST="/opt/freeware/etc/clamav/freshclam.conf"
CLAMSCAN_BIN="/opt/freeware/bin/clamscan"
FRESHCLAM_BIN="/opt/freeware/bin/freshclam"
LOG_DIR="/var/log/clamav"
DB_DIR="/var/lib/clamav"
AUDIT_LOG="${LOG_DIR}/infected_audit.log"
WEEKLY_REPORT="${LOG_DIR}/weekly_report.log"
WHITE_LIST="${DB_DIR}/whitelist.txt"
SCAN_CHECKPOINT="${DB_DIR}/scan_checkpoint"
SETUP_COMPLETE="${DB_DIR}/setup_complete"
SCAN_SCRIPT="/usr/local/bin/aix_clamav_scan.sh"
FRESHCLAM_SCRIPT="/usr/local/bin/aix_freshclam.sh"
REPORT_SCRIPT="/usr/local/bin/aix_clamav_weekly_report.sh"
XLCLIB_DIR="/usr/lpp/xlC/lib"
LIBUNWIND_SO="/usr/lpp/xlC/lib/libunwind.a"
LIBUNWIND_LINK="/usr/lib/libunwind.a"
PROFILE_FILE="/etc/profile"

# ── check_root ────────────────────────────────────────────────────────────────
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        printf "${RED}Error: This script must be run as root.${NC}\n"
        exit 1
    fi
}

# ── confirm_action ────────────────────────────────────────────────────────────
confirm_action() {
    printf "Are you sure you want to continue? (y/n): "
    read -r CHOICE
    case "$CHOICE" in
        y|Y) return 0 ;;
        n|N) exit 1 ;;
        *)
            print "Invalid input. Please enter 'y' or 'n'."
            confirm_action
            ;;
    esac
}

# ── set_libpath ───────────────────────────────────────────────────────────────
set_libpath() {
    if [ -z "$LIBPATH" ]; then
        export LIBPATH=/opt/freeware/lib:/usr/lib:/usr/lpp/xlC/lib
    else
        export LIBPATH=/opt/freeware/lib:/usr/lpp/xlC/lib:$LIBPATH
    fi
}

# ── sed_inplace — AIX-safe in-place sed ──────────────────────────────────────
# Usage: sed_inplace 'expression' /path/to/file
sed_inplace() {
    typeset _expr="$1"
    typeset _file="$2"
    typeset _tmp
    _tmp=$(mktemp /tmp/clamav_sed_XXXXXX)
    sed "$_expr" "$_file" > "$_tmp" && cp "$_tmp" "$_file"
    rm -f "$_tmp"
}

# ── check_network ─────────────────────────────────────────────────────────────
check_network() {
    typeset _host="$1"
    if ping -c 1 -w 5 "$_host" >/dev/null 2>&1; then
        return 0
    else
        printf "${RED}[ERROR] Cannot reach ${_host}. Check network connectivity.${NC}\n"
        return 1
    fi
}

# ── print_version ─────────────────────────────────────────────────────────────
print_version() {
printf "\n${CYAN}========================================================${NC}\n"
printf "${CYAN}|                                                      |${NC}\n"
printf "${CYAN}|        C L A M A V   A I X   E D I T I O N          |${NC}\n"
printf "${CYAN}|    Antivirus Management Suite for AIX 7.1/7.2/7.3     |${NC}\n"
printf "${CYAN}|                     Ver: 2.3.1                       |${NC}\n"
printf "${CYAN}|                                                      |${NC}\n"
printf "${CYAN}========================================================${NC}\n"
printf "${CYAN}\nAuthor: Mark Pierce-Zellfrow ${NC}\n"
printf "${YELLOW}\n  Ver  |    Date   |                         Changes                       ${NC}\n"
printf "${YELLOW}=================================================================================${NC}\n"
printf "${MAGENTA} 1.0.0 | 05/29/2026 | - Initial release - AIX ClamAV port ${NC}\n"
printf "${MAGENTA} 1.0.1 | 05/29/2026 | - Stage function created ${NC}\n"
printf "${MAGENTA} 1.0.2 | 05/29/2026 | - Install/setup function created ${NC}\n"
printf "${MAGENTA} 1.0.3 | 05/29/2026 | - Health check function created ${NC}\n"
printf "${MAGENTA} 1.0.4 | 05/29/2026 | - Freshclam update function created ${NC}\n"
printf "${MAGENTA} 1.0.5 | 05/29/2026 | - Test scan and directory scan functions created ${NC}\n"
printf "${MAGENTA} 1.0.6 | 05/29/2026 | - Uninstall function created ${NC}\n"
printf "${MAGENTA} 1.0.7 | 05/29/2026 | - Scan automation and AIX cron setup added ${NC}\n"
printf "${MAGENTA} 1.0.8 | 05/29/2026 | - LIBPATH and libunwind configuration added ${NC}\n"
printf "${MAGENTA} 1.0.9 | 05/29/2026 | - Whitelist manager added ${NC}\n"
printf "${MAGENTA} 2.0.0 | 06/04/2026 | - Staging changed to file-check + directions; no SCP performed by script ${NC}\n"
printf "${MAGENTA} 2.1.0 | 06/04/2026 | - Log server and SCP shipping removed entirely ${NC}\n"
printf "${MAGENTA} 2.2.0 | 06/04/2026 | - --copycvd removed; incremental scanning with find -newer + --file-list ${NC}\n"
printf "${MAGENTA} 2.2.1 | 06/04/2026 | - --manualscan added to trigger on-demand full system scan ${NC}\n"
printf "${MAGENTA} 2.3.0 | 06/04/2026 | - Enhanced --clamavcheck: virus DB version, build date, last freshclam run ${NC}\n"
printf "${MAGENTA} 2.3.1 | 06/04/2026 | - Test suite merged into script as --runtests; clamav_test.ksh removed ${NC}\n"
}

# ── print_help ────────────────────────────────────────────────────────────────
print_help() {
printf "\n${MAGENTA}Basic syntax:${NC}\n"
printf "${YELLOW}ksh clamav.ksh <OPTION>${NC}\n"
printf "\n${MAGENTA}clamav.ksh Based Options:${NC}\n"
printf "${YELLOW}--help${NC}              # Gives script overview information\n\n"
printf "${YELLOW}--ver${NC}               # Gives script versioning related information\n\n"
printf "\n${MAGENTA}Staging Options:${NC}\n"
printf "${YELLOW}--stageclamav${NC}       # Checks if required files are staged in /SCC-TMP/clamaix; prints placement directions if missing\n\n"
printf "\n${MAGENTA}Installation Options:${NC}\n"
printf "${YELLOW}--setupclamav${NC}       # Full ClamAV installation and configuration on AIX\n\n"
printf "${YELLOW}--freshclam${NC}         # Runs freshclam to update virus signature databases\n\n"
printf "\n${MAGENTA}Status Options:${NC}\n"
printf "${YELLOW}--clamavcheck${NC}       # Gives you full status of ClamAV on AIX\n\n"
printf "${YELLOW}--testclamav${NC}        # Tests ClamAV is working with an EICAR file and /tmp scan\n\n"
printf "${YELLOW}--scan <DIR>${NC}        # Scans a specified directory\n\n"
printf "${YELLOW}--manualscan${NC}        # Triggers an immediate incremental scan (same logic as daily cron)\n\n"
printf "\n${MAGENTA}Configuration Options:${NC}\n"
printf "${YELLOW}--whitelsclamav${NC}     # Manage the scan false positive whitelist\n\n"
printf "\n${MAGENTA}Testing Options:${NC}\n"
printf "${YELLOW}--runtests${NC}          # Run automated self-tests (--pre before install, --post after, --all for both)\n\n"
printf "\n${MAGENTA}Removal Options:${NC}\n"
printf "${YELLOW}--removeclamav${NC}      # Removes ClamAV installation from AIX\n\n"
printf "\n"
exit 0
}

# ── stage_clamav ──────────────────────────────────────────────────────────────
stage_clamav() {
    check_root
    print ""
    printf "%s\n" '========================================================='
    print "    CLAMAV AIX — STAGING CHECK"
    printf "%s\n" '========================================================='
    print ""
    print "Checking for required files in ${CLAM_STAGING}..."
    print ""

    typeset MISSING=0
    for F in \
        "${CLAM_STAGING}/clamav-1.4.3-1.aix7.2.ppc.rpm" \
        "${CLAM_STAGING}/freshclam.conf"                  \
        "${CLAM_STAGING}/libunwind.17.1.3.0.bff"; do
        if [ -f "$F" ]; then
            printf "${GREEN}[PRESENT] $F${NC}\n"
        else
            printf "${RED}[MISSING] $F${NC}\n"
            MISSING=1
        fi
    done

    if [ "$MISSING" -eq 0 ]; then
        print ""
        printf "${GREEN}[OK] All staging files are present.${NC}\n"
        print ""
        ls -l "$CLAM_STAGING"
        print ""
        print "Run the following to install:"
        printf "  ksh clamav.ksh --setupclamav\n"
        printf "%s\n" '========================================================='
        return 0
    fi

    # ── One or more files are missing — print placement directions ─────────
    print ""
    printf "${YELLOW}One or more required files are missing.${NC}\n"
    print "Place the files manually using the steps below."
    print ""
    printf "%s\n" '---------------------------------------------------------'
    print "  HOW TO STAGE THE FILES"
    printf "%s\n" '---------------------------------------------------------'
    print ""
    print "  On THIS host, as root:"
    print ""
    printf "    mkdir -p ${STAGING_DIR}\n"
    printf "    cd ${STAGING_DIR}\n"
    print ""
    print "  From a host that already has clamaix.tar (e.g. fse6-1),"
    print "  run the following ON THAT HOST to push the file here:"
    print ""
    printf "    scp /SCC-TMP/${TAR_FILE} $(hostname):${STAGING_DIR}/\n"
    print ""
    print "  Or from THIS host (you will be prompted for a password):"
    print ""
    printf "    cd ${STAGING_DIR}\n"
    printf "    scp fse6-1:/SCC-TMP/${TAR_FILE} .\n"
    print ""
    print "  Once the tar is in ${STAGING_DIR}, extract it:"
    print ""
    printf "    cd ${STAGING_DIR}\n"
    printf "    tar -xvf ${TAR_FILE}\n"
    print ""
    print "  This will create:"
    printf "    ${CLAM_STAGING}/clamav-1.4.3-1.aix7.2.ppc.rpm\n"
    printf "    ${CLAM_STAGING}/freshclam.conf\n"
    printf "    ${CLAM_STAGING}/libunwind.17.1.3.0.bff\n"
    print ""
    print "  Then re-run this check:"
    printf "    ksh clamav.ksh --stageclamav\n"
    print ""
    print "  When all files show [PRESENT], run the install:"
    printf "    ksh clamav.ksh --setupclamav\n"
    printf "%s\n" '========================================================='
    exit 1
}

# ── setup_clamav ──────────────────────────────────────────────────────────────
setup_clamav() {
    check_root
    confirm_action

    typeset EMAIL
    printf "Please enter the email address for ClamAV alerts: "
    read -r EMAIL

    print ""
    printf "%s\n" '========================================================='
    printf "  ClamAV Installation — AIX $(oslevel -r 2>/dev/null || oslevel)\n"
    print "  Do NOT cancel mid-install."
    print "  Total time: 5-25 min depending on network speed."
    printf "%s\n" '========================================================='
    print ""

    # ── Check if already installed ─────────────────────────────────────────
    if rpm -q clamav >/dev/null 2>&1; then
        printf "${YELLOW}[WARN] ClamAV is already installed on this system:${NC}\n"
        rpm -q clamav
        print ""
        printf "Proceed with reinstall/reconfigure? (y/N): "
        read -r REINSTALL
        if [[ "$REINSTALL" != "y" && "$REINSTALL" != "Y" ]]; then
            print "Exiting. No changes made."
            return 0
        fi
    fi

    # ── Check staging files exist ──────────────────────────────────────────
    print "[Pre-check] Verifying staged installation files..."
    typeset MISSING_STAGE=0
    for F in \
        "${CLAM_STAGING}/clamav-1.4.3-1.aix7.2.ppc.rpm" \
        "${CLAM_STAGING}/freshclam.conf"                  \
        "${CLAM_STAGING}/libunwind.17.1.3.0.bff"; do
        if [ ! -f "$F" ]; then
            printf "${RED}[FAIL] Missing: $F${NC}\n"
            MISSING_STAGE=1
        fi
    done

    if [ "$MISSING_STAGE" -eq 1 ]; then
        printf "${RED}[ERROR] One or more staging files are missing from ${CLAM_STAGING}.${NC}\n"
        print ""
        printf "${YELLOW}  Run the staging check for placement directions:${NC}\n"
        printf "    ksh clamav.ksh --stageclamav\n"
        print ""
        print "  Expected files:"
        printf "    ${CLAM_STAGING}/clamav-1.4.3-1.aix7.2.ppc.rpm\n"
        printf "    ${CLAM_STAGING}/freshclam.conf\n"
        printf "    ${CLAM_STAGING}/libunwind.17.1.3.0.bff\n"
        exit 1
    fi
    printf "${GREEN}[OK] All staging files present.${NC}\n"
    print ""

    # ── Set LIBPATH for this session ───────────────────────────────────────
    set_libpath
    printf "[+] LIBPATH set to: ${LIBPATH}\n"
    print ""

    # ── Step 1: Create xlC lib directory ──────────────────────────────────
    print "[Step 1/7] Creating ${XLCLIB_DIR} directory..."
    mkdir -p "$XLCLIB_DIR"
    printf "${GREEN}[OK] ${XLCLIB_DIR} ready.${NC}\n"
    print ""

    # ── Step 2: Install libunwind via restore ──────────────────────────────
    print "[Step 2/7] Installing libunwind from BFF..."
    printf "    File: ${LIBUNWIND_BFF}\n"
    print ""
    cd / || exit 1
    restore -xvqf "$LIBUNWIND_BFF"
    if [ $? -ne 0 ]; then
        printf "${RED}[ERROR] restore failed for ${LIBUNWIND_BFF}${NC}\n"
        exit 1
    fi

    if [ ! -f "$LIBUNWIND_SO" ]; then
        printf "${RED}[ERROR] ${LIBUNWIND_SO} not found after restore.${NC}\n"
        exit 1
    fi
    printf "${GREEN}[OK] libunwind.a installed at ${LIBUNWIND_SO}${NC}\n"
    print ""

    # ── Step 3: Symlink libunwind into /usr/lib ────────────────────────────
    print "[Step 3/7] Creating /usr/lib/libunwind.a symlink..."
    ln -sf "$LIBUNWIND_SO" "$LIBUNWIND_LINK"
    ls -l "$LIBUNWIND_LINK"
    print ""
    print "    Verifying library archive contents..."
    ar -X32_64 -t "$LIBUNWIND_LINK"
    if [ $? -ne 0 ]; then
        printf "${YELLOW}[WARN] ar verification failed for ${LIBUNWIND_LINK}${NC}\n"
    else
        printf "${GREEN}[OK] libunwind.a verified.${NC}\n"
    fi
    print ""

    # ── Step 4: Verify curl ────────────────────────────────────────────────
    print "[Step 4/7] Verifying curl availability..."
    if command -v curl >/dev/null 2>&1; then
        curl --version | head -1
        printf "${GREEN}[OK] curl is available.${NC}\n"
    else
        printf "${YELLOW}[WARN] curl not found in PATH. freshclam requires curl.${NC}\n"
        printf "${YELLOW}       Install from AIX Toolbox if freshclam fails.${NC}\n"
    fi
    print ""

    # ── Step 5: Install ClamAV RPM ────────────────────────────────────────
    print "[Step 5/7] Installing ClamAV RPM..."
    printf "    Package: ${CLAMAV_RPM}\n"
    print "    Using --nodeps (libunwind.a provided manually via BFF restore)"
    print ""
    rpm -Uhv --nodeps "$CLAMAV_RPM"
    if [ $? -ne 0 ]; then
        printf "${RED}[ERROR] rpm install failed.${NC}\n"
        exit 1
    fi

    if [ ! -x "$CLAMSCAN_BIN" ]; then
        printf "${RED}[ERROR] clamscan not found at ${CLAMSCAN_BIN} after install.${NC}\n"
        exit 1
    fi
    printf "${GREEN}[OK] ClamAV installed.${NC}\n"
    "$CLAMSCAN_BIN" --version
    print ""

    # ── Step 6: Copy and configure freshclam.conf ─────────────────────────
    print "[Step 6/7] Configuring freshclam..."
    mkdir -p "$(dirname "$FRESHCLAM_CONF_DEST")"
    cp "$FRESHCLAM_CONF_SRC" "$FRESHCLAM_CONF_DEST"
    if [ $? -ne 0 ]; then
        printf "${RED}[ERROR] Failed to copy freshclam.conf to ${FRESHCLAM_CONF_DEST}${NC}\n"
        exit 1
    fi
    printf "${GREEN}[OK] freshclam.conf installed at ${FRESHCLAM_CONF_DEST}${NC}\n"
    print ""

    # ── Create log and database directories ───────────────────────────────
    mkdir -p "$LOG_DIR" "$DB_DIR"
    touch "$AUDIT_LOG" "$WEEKLY_REPORT" "$WHITE_LIST"
    printf "${GREEN}[OK] Log and database directories created.${NC}\n"
    print ""

    # ── Configure LIBPATH permanently in /etc/profile ─────────────────────
    print "[+] Configuring LIBPATH in ${PROFILE_FILE}..."
    if grep -q "BEGIN ClamAV LIBPATH" "$PROFILE_FILE" 2>/dev/null; then
        printf "${YELLOW}[INFO] LIBPATH block already present in ${PROFILE_FILE}. Skipping.${NC}\n"
    else
        cat >> "$PROFILE_FILE" << 'LIBEOF'

# BEGIN ClamAV LIBPATH - added by clamav.ksh
if [ -z "$LIBPATH" ]; then
    export LIBPATH=/opt/freeware/lib:/usr/lib:/usr/lpp/xlC/lib
else
    export LIBPATH=/opt/freeware/lib:/usr/lpp/xlC/lib:$LIBPATH
fi
# END ClamAV LIBPATH
LIBEOF
        printf "${GREEN}[OK] LIBPATH block added to ${PROFILE_FILE}${NC}\n"
    fi
    print ""

    # ── Step 7: Run freshclam ─────────────────────────────────────────────
    print "[Step 7/7] Downloading virus signature databases..."
    print "    This may take 5-15 minutes depending on network speed."
    print "    main.cvd ~90MB  daily.cvd ~25MB  bytecode.cvd ~300KB"
    print ""
    printf "Run freshclam now? (y/N): "
    read -r RUN_FC
    if [[ "$RUN_FC" == "y" || "$RUN_FC" == "Y" ]]; then
        set_libpath
        "$FRESHCLAM_BIN"
        if [ $? -ne 0 ]; then
            printf "${YELLOW}[WARN] freshclam exited with errors. Database may be incomplete.${NC}\n"
            printf "${YELLOW}       Re-run with:  ksh clamav.ksh --freshclam${NC}\n"
        else
            printf "${GREEN}[OK] Virus databases updated successfully.${NC}\n"
        fi
    else
        printf "${YELLOW}[SKIP] freshclam not run.${NC}\n"
        printf "${YELLOW}       Update databases with:    ksh clamav.ksh --freshclam${NC}\n"
    fi
    print ""

    # ── Set up automation scripts and cron jobs ────────────────────────────
    setup_cron_jobs "$EMAIL"

    touch "$SETUP_COMPLETE"

    print ""
    printf "%s\n" '========================================================='
    print "  ClamAV Setup Complete on AIX."
    print ""
    print "  Next steps:"
    print "    1. Verify full health:"
    print "       ksh clamav.ksh --clamavcheck"
    print "    2. Run functionality test:"
    print "       ksh clamav.ksh --testclamav"
    print "    3. Update signatures if not done:"
    print "       ksh clamav.ksh --freshclam"
    print "    4. Scan a directory:"
    print "       ksh clamav.ksh --scan /home"
    print "    5. Run the included clamscan.sh script (optional):"
    printf "       cd ${CLAM_STAGING} && ./clamscan.sh &\n"
    printf "%s\n" '========================================================='
}

# ── setup_cron_jobs ───────────────────────────────────────────────────────────
setup_cron_jobs() {
    typeset EMAIL_ADDR="$1"

    print "[+] Writing AIX scan automation scripts..."

    # ── aix_clamav_scan.sh ────────────────────────────────────────────────
    cat > "$SCAN_SCRIPT" << 'SCANEOF'
#!/bin/ksh
# aix_clamav_scan.sh - ClamAV incremental scanner for AIX (managed by clamav.ksh)

if [ -z "$LIBPATH" ]; then
    export LIBPATH=/opt/freeware/lib:/usr/lib:/usr/lpp/xlC/lib
else
    export LIBPATH=/opt/freeware/lib:/usr/lpp/xlC/lib:$LIBPATH
fi

CLAMSCAN=/opt/freeware/bin/clamscan
TYPE=${1:-Daily}
LOCKFILE="/tmp/aix_clamav_scan.lock"
EMAIL_ADDR="__EMAIL__"
CHK="/var/lib/clamav/scan_checkpoint"
AUDIT_LOG="/var/log/clamav/infected_audit.log"
WEEKLY="/var/log/clamav/weekly_report.log"
WHITE_LIST="/var/lib/clamav/whitelist.txt"
LOG_DIR="/var/log/clamav"
TODAY=$(date '+%Y-%m-%d')
DATED_LOG="${LOG_DIR}/clamav-${TODAY}.log"
NOW=$(date '+%Y-%m-%d %H:%M:%S')

mkdir -p "$LOG_DIR"
touch "$AUDIT_LOG" "$WEEKLY"

# ── Prevent parallel scans via PID lock ──────────────────────────────────────
if [ -f "$LOCKFILE" ]; then
    LOCK_PID=$(cat "$LOCKFILE" 2>/dev/null)
    if [ -n "$LOCK_PID" ] && kill -0 "$LOCK_PID" 2>/dev/null; then
        exit 1
    fi
fi
echo $$ > "$LOCKFILE"
trap "rm -f $LOCKFILE" EXIT INT TERM

# ── Determine scan target and arguments ──────────────────────────────────────
if [ "$TYPE" = "MANUAL-TEST" ]; then
    printf '%s\n' 'X5O!P%@AP[4\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*' \
        > /tmp/eicar_test.com 2>/dev/null
    SCAN_ARGS="-i /tmp/eicar_test.com"
elif [ ! -f "$CHK" ]; then
    TYPE="Full-Initial"
    echo "$NOW [INFO] No checkpoint — performing initial full system scan." >> "$AUDIT_LOG"
    SCAN_ARGS="-r -i \
        --exclude-dir=^/proc \
        --exclude-dir=^/dev  \
        --exclude-dir=^/sys  \
        --exclude-dir=^/var/lib/clamav \
        --exclude-dir=^/var/log/clamav \
        /"
else
    # ── Incremental scan: only files newer than last checkpoint ──────────────
    CHK_NEW="/var/lib/clamav/scan_checkpoint.new"
    FILE_LIST_TMP=$(mktemp /tmp/clamav_filelist_XXXXXX)
    touch "$CHK_NEW"
    find / \( \
        -path /proc -o \
        -path /dev  -o \
        -path /sys  -o \
        -path /var/lib/clamav -o \
        -path /var/log/clamav \
    \) -prune -o -newer "$CHK" -type f -print > "$FILE_LIST_TMP" 2>/dev/null
    FILE_COUNT=$(wc -l < "$FILE_LIST_TMP" | awk '{print $1}')
    if [ "$FILE_COUNT" -eq 0 ]; then
        echo "Date: $NOW | Type: $TYPE | Files: 0 | Infected: 0 | No changes since last scan." >> "$DATED_LOG"
        rm -f "$FILE_LIST_TMP" "$CHK_NEW"
        mv "$CHK_NEW" "$CHK" 2>/dev/null || touch "$CHK"
        rm -f "$LOCKFILE"
        exit 0
    fi
    SCAN_ARGS="-i --file-list=$FILE_LIST_TMP"
fi

# ── Run scan ──────────────────────────────────────────────────────────────────
SCAN_TMP=$(mktemp /tmp/clamav_out_XXXXXX)
{
    echo "=== ClamAV Scan: $NOW | Type: $TYPE ==="
    nice -n 17 $CLAMSCAN $SCAN_ARGS 2>&1
} > "$SCAN_TMP"
SCAN_RC=$?
cat "$SCAN_TMP" >> "$DATED_LOG"

# ── Parse results ─────────────────────────────────────────────────────────────
INFECTED_COUNT=$(grep "Infected files:" "$SCAN_TMP" | awk '{print $NF}')
[ -z "$INFECTED_COUNT" ] && INFECTED_COUNT=0

FILES_SCANNED=$(grep "Scanned files:" "$SCAN_TMP" | awk '{print $NF}')
[ -z "$FILES_SCANNED" ] && FILES_SCANNED=0

FOUND_LINES=$(grep "FOUND" "$SCAN_TMP")
rm -f "$SCAN_TMP"
[ -n "$FILE_LIST_TMP" ] && rm -f "$FILE_LIST_TMP"

# ── Whitelist filtering ───────────────────────────────────────────────────────
if [ "$INFECTED_COUNT" -gt 0 ] && [ -s "$WHITE_LIST" ]; then
    REAL_INFECTED=0
    FILTERED_FOUND=""
    echo "$FOUND_LINES" | while IFS= read -r FOUND_LINE; do
        [ -z "$FOUND_LINE" ] && continue
        FOUND_PATH=$(echo "$FOUND_LINE" | sed 's/: .* FOUND$//')
        if grep -qx "$FOUND_PATH" "$WHITE_LIST" 2>/dev/null; then
            echo "$NOW [WHITELIST] Suppressed alert for: $FOUND_PATH" >> "$AUDIT_LOG"
        else
            REAL_INFECTED=$((REAL_INFECTED + 1))
        fi
    done
fi

END_TIME=$(date '+%Y-%m-%d %H:%M:%S')

# ── Log detection events and send alert ──────────────────────────────────────
if [ "$INFECTED_COUNT" -gt 0 ]; then
    {
        echo "=============================="
        echo "Detection Event: $NOW"
        echo "Scan Type:       $TYPE"
        echo "Files Scanned:   $FILES_SCANNED"
        echo "Infected Count:  $INFECTED_COUNT"
        echo "Detected Files:"
        echo "$FOUND_LINES"
        echo "=============================="
    } >> "$AUDIT_LOG"

    echo "CRITICAL: Virus Detected on $(hostname) [$TYPE] — $INFECTED_COUNT file(s)" | \
        mail -s "CRITICAL: Virus Detected on $(hostname) [$TYPE]" "$EMAIL_ADDR"
fi

echo "Date: $NOW | Type: $TYPE | Files: $FILES_SCANNED | Infected: $INFECTED_COUNT | End: $END_TIME" >> "$WEEKLY"

# ── Advance checkpoint (not on test runs, not on scan error) ─────────────────
if [ "$TYPE" != "MANUAL-TEST" ] && [ "${SCAN_RC:-0}" -ne 2 ]; then
    if [ -f "$CHK_NEW" ]; then
        mv "$CHK_NEW" "$CHK"
    else
        touch "$CHK"
    fi
fi

touch /var/lib/clamav/setup_complete
SCANEOF

    # ── aix_freshclam.sh ──────────────────────────────────────────────────
    cat > "$FRESHCLAM_SCRIPT" << 'FCEOF'
#!/bin/ksh
# aix_freshclam.sh - freshclam wrapper for AIX (managed by clamav.ksh)

if [ -z "$LIBPATH" ]; then
    export LIBPATH=/opt/freeware/lib:/usr/lib:/usr/lpp/xlC/lib
else
    export LIBPATH=/opt/freeware/lib:/usr/lpp/xlC/lib:$LIBPATH
fi

LOG_DIR="/var/log/clamav"
TODAY=$(date '+%Y-%m-%d')
FC_LOG="${LOG_DIR}/freshclam-${TODAY}.log"

mkdir -p "$LOG_DIR"
echo "freshclam run: $(date '+%Y-%m-%d %H:%M:%S')" >> "$FC_LOG"
/opt/freeware/bin/freshclam 2>&1 | tee -a "$FC_LOG"
FC_RC=$?
if [ $FC_RC -ne 0 ]; then
    echo "[WARN] freshclam exited with code $FC_RC at $(date '+%Y-%m-%d %H:%M:%S')" >> "$FC_LOG"
fi
FCEOF

    # ── aix_clamav_weekly_report.sh ───────────────────────────────────────
    cat > "$REPORT_SCRIPT" << 'RPTEOF'
#!/bin/ksh
# aix_clamav_weekly_report.sh - ClamAV weekly summary report for AIX

if [ -z "$LIBPATH" ]; then
    export LIBPATH=/opt/freeware/lib:/usr/lib:/usr/lpp/xlC/lib
else
    export LIBPATH=/opt/freeware/lib:/usr/lpp/xlC/lib:$LIBPATH
fi

EMAIL_ADDR="__EMAIL__"
WEEKLY="/var/log/clamav/weekly_report.log"
AUDIT_LOG="/var/log/clamav/infected_audit.log"
HOST=$(hostname)
NOW=$(date '+%Y-%m-%d %H:%M:%S')

[ ! -f "$WEEKLY" ] && exit 0

TOTAL_FILES=0
TOTAL_INFECTED=0
TOTAL_SCANS=0

while IFS= read -r LINE; do
    [ -z "$LINE" ] && continue
    FILES=$(echo    "$LINE" | sed -n 's/.*Files: \([0-9]*\).*/\1/p')
    INFECTED=$(echo "$LINE" | sed -n 's/.*Infected: \([0-9]*\).*/\1/p')
    TOTAL_FILES=$((TOTAL_FILES + ${FILES:-0}))
    TOTAL_INFECTED=$((TOTAL_INFECTED + ${INFECTED:-0}))
    TOTAL_SCANS=$((TOTAL_SCANS + 1))
done < "$WEEKLY"

if [ "$TOTAL_INFECTED" -eq 0 ]; then
    VERDICT="SYSTEM STATUS: CLEAN — No threats detected this week."
    SUBJECT="ClamAV Weekly Report — CLEAN — $HOST"
else
    VERDICT="SYSTEM STATUS: ACTION REQUIRED — $TOTAL_INFECTED infected file(s) detected."
    SUBJECT="ClamAV Weekly Report — $TOTAL_INFECTED THREAT(S) DETECTED — $HOST"
fi

{
    echo "======================================================"
    echo "  CLAMAV WEEKLY SECURITY REPORT"
    echo "======================================================"
    echo "  Host        : $HOST"
    echo "  Report Date : $NOW"
    echo "======================================================"
    echo "  $VERDICT"
    echo "======================================================"
    echo "  Total Scans Run    : $TOTAL_SCANS"
    echo "  Total Files Scanned: $TOTAL_FILES"
    echo "  Total Threats Found: $TOTAL_INFECTED"
    echo "======================================================"
    echo "  SCAN LOG (last 20 entries):"
    tail -20 "$WEEKLY" 2>/dev/null || echo "  No entries found."
    echo "======================================================"
    echo "  AUDIT LOG (last 20 lines):"
    tail -20 "$AUDIT_LOG" 2>/dev/null || echo "  No audit entries found."
    echo "======================================================"
} | mail -s "$SUBJECT" "$EMAIL_ADDR"

> "$WEEKLY"
RPTEOF

    # ── Substitute email address into all scripts ─────────────────────────
    for SCRIPT in "$SCAN_SCRIPT" "$FRESHCLAM_SCRIPT" "$REPORT_SCRIPT"; do
        typeset TMP_S
        TMP_S=$(mktemp /tmp/clamav_subs_XXXXXX)
        sed "s|__EMAIL__|${EMAIL_ADDR}|g" "$SCRIPT" > "$TMP_S" && cp "$TMP_S" "$SCRIPT"
        rm -f "$TMP_S"
    done

    chmod 700 "$SCAN_SCRIPT" "$FRESHCLAM_SCRIPT" "$REPORT_SCRIPT"

    # ── Install cron jobs on AIX ───────────────────────────────────────────
    print "[+] Configuring cron jobs..."

    # Backup existing crontab
    typeset CRON_BACKUP="/var/spool/cron/crontabs/root.bak.$(date '+%Y%m%d%H%M%S')"
    crontab -l > "$CRON_BACKUP" 2>/dev/null

    # Build new crontab — remove old clamav entries, append new ones
    typeset TMP_CRON
    TMP_CRON=$(mktemp /tmp/crontab_XXXXXX)
    crontab -l 2>/dev/null | grep -v "aix_clamav_scan\|aix_freshclam\|aix_clamav_weekly" > "$TMP_CRON"
    cat >> "$TMP_CRON" << CRONEOF
# ClamAV automated jobs — added by clamav.ksh
0    1 * * *  ${SCAN_SCRIPT} Daily
0    2 * * *  ${FRESHCLAM_SCRIPT}
0    9 * * 0  ${REPORT_SCRIPT}
CRONEOF

    crontab "$TMP_CRON"
    typeset _CRON_RC=$?
    rm -f "$TMP_CRON"

    if crontab -l 2>/dev/null | grep -q "aix_clamav_scan"; then
        printf "${GREEN}[OK] Cron jobs installed.${NC}\n"
    else
        typeset _SPOOL="/var/spool/cron/crontabs/root"
        printf "${YELLOW}[WARN] crontab cmd failed (rc=${_CRON_RC}), writing direct...${NC}\n"
        grep -v "aix_clamav_scan\|aix_freshclam\|aix_clamav_weekly" "$_SPOOL" 2>/dev/null > /tmp/clamav_cron_direct
        printf "# ClamAV automated jobs — added by clamav.ksh\n" >> /tmp/clamav_cron_direct
        printf "0    1 * * *  ${SCAN_SCRIPT} Daily\n" >> /tmp/clamav_cron_direct
        printf "0    2 * * *  ${FRESHCLAM_SCRIPT}\n" >> /tmp/clamav_cron_direct
        printf "0    9 * * 0  ${REPORT_SCRIPT}\n" >> /tmp/clamav_cron_direct
        cp /tmp/clamav_cron_direct "$_SPOOL" && chmod 600 "$_SPOOL"
        rm -f /tmp/clamav_cron_direct
        crontab -l 2>/dev/null | grep -q "aix_clamav_scan" && \
            printf "${GREEN}[OK] Cron jobs installed (direct spool write).${NC}\n" || \
            printf "${RED}[FAIL] Could not install cron jobs. Add manually to root crontab.${NC}\n"
    fi
    printf "     Daily scan:      ${SCAN_SCRIPT} (01:00)\n"
    printf "     Daily freshclam: ${FRESHCLAM_SCRIPT} (02:00)\n"
    printf "     Weekly report:   ${REPORT_SCRIPT} (Sunday 09:00)\n"
    print ""
}

# ── run_freshclam ─────────────────────────────────────────────────────────────
run_freshclam() {
    check_root
    set_libpath
    print ""
    printf "%s\n" '========================================================='
    print "    CLAMAV — FRESHCLAM UPDATE"
    printf "%s\n" '========================================================='
    print ""
    print "Updating virus signature databases..."
    print "This may take several minutes depending on network speed."
    print ""

    "$FRESHCLAM_BIN"
    typeset RC=$?

    print ""
    if [ $RC -eq 0 ]; then
        printf "${GREEN}[OK] Virus databases updated successfully.${NC}\n"
    else
        printf "${YELLOW}[WARN] freshclam exited with code ${RC}.${NC}\n"
        printf "${YELLOW}       If the download was partial or internet is unavailable,${NC}\n"
        printf "${YELLOW}       Re-run with: ksh clamav.ksh --freshclam${NC}\n"
    fi
    printf "%s\n" '========================================================='
}

# ── clamav_health_check ───────────────────────────────────────────────────────
clamav_health_check() {
    check_root
    set_libpath
    print ""
    printf "%s\n" '========================================================='
    printf "    CLAMAV AIX SYSTEM CHECK-UP — $(hostname)\n"
    printf "%s\n" '========================================================='
    print ""

    # ── Installation ──────────────────────────────────────────────────────
    printf "%s\n" '--- [Installation] ---'
    if rpm -q clamav >/dev/null 2>&1; then
        printf "${GREEN}[OK]   ClamAV is installed: $(rpm -q clamav)${NC}\n"
    else
        printf "${RED}[FAIL] ClamAV is NOT installed. Run --setupclamav.${NC}\n"
    fi
    print ""

    # ── Binaries ──────────────────────────────────────────────────────────
    printf "%s\n" '--- [Binaries] ---'
    for BIN in clamscan freshclam; do
        typeset BIN_PATH="/opt/freeware/bin/${BIN}"
        if [ -x "$BIN_PATH" ]; then
            printf "${GREEN}[OK]   ${BIN_PATH}${NC}\n"
        else
            printf "${RED}[FAIL] ${BIN_PATH} — NOT FOUND${NC}\n"
        fi
    done
    if [ -x "$CLAMSCAN_BIN" ]; then
        printf "       Version: $("$CLAMSCAN_BIN" --version 2>/dev/null)\n"
    fi
    print ""

    # ── Libraries ─────────────────────────────────────────────────────────
    printf "%s\n" '--- [Libraries] ---'
    if [ -L "$LIBUNWIND_LINK" ]; then
        printf "${GREEN}[OK]   ${LIBUNWIND_LINK}${NC}\n"
        ls -l "$LIBUNWIND_LINK"
    else
        printf "${RED}[FAIL] ${LIBUNWIND_LINK} — symlink missing${NC}\n"
    fi
    if [ -f "$LIBUNWIND_SO" ]; then
        printf "${GREEN}[OK]   ${LIBUNWIND_SO}${NC}\n"
    else
        printf "${RED}[FAIL] ${LIBUNWIND_SO} — missing${NC}\n"
    fi
    print ""

    # ── LIBPATH ───────────────────────────────────────────────────────────
    printf "%s\n" '--- [LIBPATH] ---'
    if echo "${LIBPATH}" | grep -q "/opt/freeware/lib"; then
        printf "${GREEN}[OK]   LIBPATH includes /opt/freeware/lib${NC}\n"
    else
        printf "${YELLOW}[WARN] LIBPATH may not include /opt/freeware/lib${NC}\n"
    fi
    printf "       Current LIBPATH: ${LIBPATH:-<not set>}\n"
    if grep -q "BEGIN ClamAV LIBPATH" "$PROFILE_FILE" 2>/dev/null; then
        printf "${GREEN}[OK]   LIBPATH block present in ${PROFILE_FILE}${NC}\n"
    else
        printf "${YELLOW}[WARN] LIBPATH not configured in ${PROFILE_FILE}${NC}\n"
    fi
    print ""

    # ── Configuration ─────────────────────────────────────────────────────
    printf "%s\n" '--- [Configuration] ---'
    if [ -f "$FRESHCLAM_CONF_DEST" ]; then
        printf "${GREEN}[OK]   ${FRESHCLAM_CONF_DEST}${NC}\n"
    else
        printf "${RED}[FAIL] ${FRESHCLAM_CONF_DEST} — missing${NC}\n"
    fi
    print ""

    # ── Virus Databases ─────────────────────────────────────────────────────
    printf "--- [Virus Databases] ---\n"
    typeset DB_OK=0
    for DB in daily.cvd daily.cld main.cvd main.cld bytecode.cvd bytecode.cld; do
        if [ -f "${DB_DIR}/${DB}" ]; then
            typeset DB_KB DB_MTIME
            DB_KB=$(ls -l "${DB_DIR}/${DB}" 2>/dev/null | awk '{printf "%.0f", $5/1024}')
            DB_MTIME=$(ls -l "${DB_DIR}/${DB}" 2>/dev/null | awk '{print $6, $7, $8}')
            printf "${GREEN}[OK]   %-30s %8s KB  modified: %s${NC}\n" "$DB" "$DB_KB" "$DB_MTIME"
            DB_OK=1
        fi
    done
    if [ "$DB_OK" -eq 0 ]; then
        printf "${RED}[FAIL] No virus databases found in ${DB_DIR}${NC}\n"
        printf "${YELLOW}       Run: ksh clamav.ksh --freshclam${NC}\n"
    fi
    if [ "$DB_OK" -eq 1 ]; then
        typeset CLAM_VER_LINE DB_VER DB_DATE
        CLAM_VER_LINE=$("$CLAMSCAN_BIN" --version 2>/dev/null)
        DB_VER=$(printf '%s' "$CLAM_VER_LINE" | awk -F'/' '{print $2}')
        DB_DATE=$(printf '%s' "$CLAM_VER_LINE" | awk -F'/' '{print $3}')
        [ -n "$DB_VER" ] && printf "${CYAN}       Definition version : %s${NC}\n" "$DB_VER"
        [ -n "$DB_DATE" ] && printf "${CYAN}       Definition built   : %s${NC}\n" "$DB_DATE"
        # Last freshclam run — check script log, fall back to DB file mtime
        typeset LATEST_FC
        LATEST_FC=$(ls "${LOG_DIR}"/freshclam-*.log 2>/dev/null | sort | tail -1)
        if [ -n "$LATEST_FC" ]; then
            typeset FC_LAST
            FC_LAST=$(grep "^freshclam run:" "$LATEST_FC" 2>/dev/null | tail -1 | sed 's/freshclam run: //')
            [ -z "$FC_LAST" ] && FC_LAST=$(ls -l "$LATEST_FC" 2>/dev/null | awk '{print $6, $7, $8}')
            printf "${CYAN}       Last freshclam run : %s${NC}\n" "$FC_LAST"
        else
            typeset FC_MTIME
            for _DB in daily.cvd daily.cld; do
                [ -f "${DB_DIR}/${_DB}" ] && FC_MTIME=$(ls -l "${DB_DIR}/${_DB}" 2>/dev/null | awk '{print $6, $7, $8}') && break
            done
            if [ -n "$FC_MTIME" ]; then
                printf "${CYAN}       Last freshclam run : ~%s (inferred from DB mtime)${NC}\n" "$FC_MTIME"
            else
                printf "${YELLOW}       No freshclam log — run: ksh clamav.ksh --freshclam${NC}\n"
            fi
        fi
    fi
    print ""

    # ── Path and File Validation    # ── Path and File Validation ──────────────────────────────────────────
    printf "%s\n" '--- [Path & File Validation] ---'
    for _CP in "$LOG_DIR"        \
               "$AUDIT_LOG"      \
               "$DB_DIR"         \
               "$WHITE_LIST"     \
               "$SCAN_SCRIPT"    \
               "$FRESHCLAM_SCRIPT" \
               "$REPORT_SCRIPT"  \
               "$SETUP_COMPLETE"; do
        if [ -e "$_CP" ]; then
            printf "${GREEN}[OK]   ${_CP}${NC}\n"
        else
            printf "${YELLOW}[MISS] ${_CP}${NC}\n"
        fi
    done
    print ""

    # ── Cron Jobs ─────────────────────────────────────────────────────────
    printf "%s\n" '--- [Cron Jobs] ---'
    if crontab -l 2>/dev/null | grep -q "aix_clamav_scan"; then
        printf "${GREEN}[OK]   Daily scan cron job present.${NC}\n"
    else
        printf "${YELLOW}[MISS] Daily scan cron job not found.${NC}\n"
    fi
    if crontab -l 2>/dev/null | grep -q "aix_freshclam"; then
        printf "${GREEN}[OK]   Daily freshclam cron job present.${NC}\n"
    else
        printf "${YELLOW}[MISS] Daily freshclam cron job not found.${NC}\n"
    fi
    if crontab -l 2>/dev/null | grep -q "aix_clamav_weekly"; then
        printf "${GREEN}[OK]   Weekly report cron job present.${NC}\n"
    else
        printf "${YELLOW}[MISS] Weekly report cron job not found.${NC}\n"
    fi
    print ""

    # ── Recent Scan Activity ──────────────────────────────────────────────
    printf "%s\n" '--- [Recent Scan Activity (last 5)] ---'
    if [ -f "$WEEKLY_REPORT" ] && [ -s "$WEEKLY_REPORT" ]; then
        tail -5 "$WEEKLY_REPORT"
    else
        print "No recent scan activity recorded."
    fi
    print ""

    # ── Infected File Audit Log ───────────────────────────────────────────
    printf "%s\n" '--- [Infected File Audit Log (last 30 lines)] ---'
    if [ -f "$AUDIT_LOG" ] && [ -s "$AUDIT_LOG" ]; then
        tail -30 "$AUDIT_LOG"
    else
        print "No infections recorded yet."
    fi
    printf "%s\n" '========================================================='
}

# ── test_clamav_setup ─────────────────────────────────────────────────────────
test_clamav_setup() {
    check_root
    set_libpath
    print ""
    printf "%s\n" '========================================================='
    print "       CLAMAV AIX FUNCTIONALITY TEST"
    printf "%s\n" '========================================================='

    print "[+] Verifying clamscan binary..."
    if [ ! -x "$CLAMSCAN_BIN" ]; then
        printf "${RED}[ERROR] clamscan not found at ${CLAMSCAN_BIN}. Run --setupclamav.${NC}\n"
        return 1
    fi
    printf "${GREEN}[OK] ${CLAMSCAN_BIN} found.${NC}\n"
    print ""

    print "[+] Verifying virus databases..."
    typeset DB_FOUND=0
    for DB in daily.cvd daily.cld main.cvd main.cld; do
        [ -f "${DB_DIR}/${DB}" ] && DB_FOUND=1
    done
    if [ "$DB_FOUND" -eq 0 ]; then
        printf "${RED}[ERROR] No virus databases found in ${DB_DIR}.${NC}\n"
        printf "${YELLOW}        Run --freshclam to download databases.${NC}\n"
        return 1
    fi
    printf "${GREEN}[OK] Virus databases present.${NC}\n"
    print ""

    print "[+] Generating EICAR test file at /tmp/eicar_test.com..."
    printf '%s\n' 'X5O!P%@AP[4\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*' \
        > /tmp/eicar_test.com 2>/dev/null
    chmod 644 /tmp/eicar_test.com
    print ""

    print "[+] Scanning EICAR test file..."
    "$CLAMSCAN_BIN" /tmp/eicar_test.com
    typeset EICAR_RC=$?
    rm -f /tmp/eicar_test.com
    print ""

    if [ "$EICAR_RC" -eq 1 ]; then
        printf "${GREEN}[PASS] EICAR test file detected — ClamAV is working correctly.${NC}\n"
        print "[INFO] File was NOT quarantined (detection-only mode confirmed)."
    elif [ "$EICAR_RC" -eq 0 ]; then
        printf "${YELLOW}[WARN] EICAR test file not detected. Databases may be incomplete.${NC}\n"
        printf "${YELLOW}       Run --freshclam to update signature databases.${NC}\n"
    else
        printf "${YELLOW}[WARN] clamscan returned code ${EICAR_RC} — check configuration.${NC}\n"
    fi

    print ""
    print "[+] Running a scan of /tmp..."
    "$CLAMSCAN_BIN" /tmp
    print ""
    printf "%s\n" '========================================================='
}

# ── scan_directory ────────────────────────────────────────────────────────────
scan_directory() {
    check_root
    set_libpath
    typeset SCAN_DIR="${1:-/tmp}"

    if [ ! -d "$SCAN_DIR" ]; then
        printf "${RED}[ERROR] Directory not found: ${SCAN_DIR}${NC}\n"
        exit 1
    fi

    mkdir -p "$LOG_DIR"
    typeset TODAY_DATE
    TODAY_DATE=$(date '+%Y-%m-%d')
    typeset DATED_LOG="${LOG_DIR}/clamav-${TODAY_DATE}.log"

    print ""
    printf "%s\n" '========================================================='
    printf "    CLAMAV AIX SCAN — ${SCAN_DIR}\n"
    printf "%s\n" '========================================================='
    printf "Scanning: ${SCAN_DIR}\n"
    printf "Log:      ${DATED_LOG}\n\n"

    # Capture scan output and exit code cleanly (avoids tee pipe exit code issue)
    typeset SCAN_TMP
    SCAN_TMP=$(mktemp /tmp/clamav_out_XXXXXX)
    "$CLAMSCAN_BIN" -r "$SCAN_DIR" 2>&1 > "$SCAN_TMP"
    typeset SCAN_RC=$?
    cat "$SCAN_TMP" | tee -a "$DATED_LOG"
    rm -f "$SCAN_TMP"

    print ""
    if [ "$SCAN_RC" -eq 0 ]; then
        printf "${GREEN}[CLEAN] No threats found in ${SCAN_DIR}${NC}\n"
    elif [ "$SCAN_RC" -eq 1 ]; then
        printf "${RED}[ALERT] Threats detected in ${SCAN_DIR}${NC}\n"
        printf "${RED}        See log: ${DATED_LOG}${NC}\n"
    else
        printf "${YELLOW}[WARN] clamscan returned code ${SCAN_RC}${NC}\n"
    fi
    printf "%s\n" '========================================================='
}

# ── clamav_whitelist_file ─────────────────────────────────────────────────────
clamav_whitelist_file() {
    check_root
    print ""
    printf "%s\n" '========================================================='
    printf "    CLAMAV WHITELIST MANAGER — $(hostname)\n"
    printf "%s\n" '========================================================='
    print ""
    printf "%s\n" '--- [Current Whitelist] ---'
    if [ -s "$WHITE_LIST" ]; then
        cat -n "$WHITE_LIST"
    else
        print "  (empty — no paths whitelisted yet)"
    fi
    print ""
    print "Options:"
    print "  1) Add a file path to the whitelist"
    print "  2) Remove a file path from the whitelist"
    print "  3) View full whitelist"
    print "  4) Exit"
    print ""
    printf "Select option [1-4]: "
    read -r OPT

    case "$OPT" in
        1)
            print ""
            print "Enter the FULL absolute path of the file to whitelist."
            print "Example: /opt/app/legit_binary"
            printf "Full file path: "
            read -r FILE_PATH
            FILE_PATH=$(echo "$FILE_PATH" | sed 's/[[:space:]]*$//')

            if [ -z "$FILE_PATH" ]; then
                printf "${RED}[ERROR] No path entered.${NC}\n"
                return 1
            fi

            if [ ! -e "$FILE_PATH" ]; then
                printf "${YELLOW}[WARN] Path does not currently exist on disk: $FILE_PATH${NC}\n"
                printf "Add it anyway? (y/N): "
                read -r CONFIRM_MISSING
                if [[ "$CONFIRM_MISSING" != "y" && "$CONFIRM_MISSING" != "Y" ]]; then
                    print "Aborted."
                    return 0
                fi
            fi

            if grep -qx "$FILE_PATH" "$WHITE_LIST" 2>/dev/null; then
                print "[INFO] Already whitelisted. No change made."
                return 0
            fi

            echo "$FILE_PATH" >> "$WHITE_LIST"
            typeset TMP_WL
            TMP_WL=$(mktemp /tmp/whitelist_XXXXXX)
            sort -u "$WHITE_LIST" > "$TMP_WL" && cp "$TMP_WL" "$WHITE_LIST"
            rm -f "$TMP_WL"

            {
                echo "=============================="
                echo "Whitelist Addition: $(date '+%Y-%m-%d %H:%M:%S')"
                echo "Path:  $FILE_PATH"
                echo "By:    root"
                echo "=============================="
            } >> "$AUDIT_LOG"

            printf "${GREEN}[SUCCESS] '${FILE_PATH}' added to whitelist.${NC}\n"
            print "[INFO]    Active immediately on next scan."
            ;;

        2)
            [ ! -s "$WHITE_LIST" ] && print "[INFO] Whitelist is empty." && return 0
            print ""
            printf "Full file path to remove: "
            read -r REMOVE_PATH
            REMOVE_PATH=$(echo "$REMOVE_PATH" | sed 's/[[:space:]]*$//')

            if ! grep -qx "$REMOVE_PATH" "$WHITE_LIST" 2>/dev/null; then
                printf "${RED}[ERROR] '${REMOVE_PATH}' not found in whitelist.${NC}\n"
                return 1
            fi

            typeset TMP_WL2
            TMP_WL2=$(mktemp /tmp/whitelist_XXXXXX)
            grep -vx "$REMOVE_PATH" "$WHITE_LIST" > "$TMP_WL2"
            cp "$TMP_WL2" "$WHITE_LIST"
            rm -f "$TMP_WL2"

            {
                echo "=============================="
                echo "Whitelist Removal: $(date '+%Y-%m-%d %H:%M:%S')"
                echo "Path:  $REMOVE_PATH"
                echo "By:    root"
                echo "=============================="
            } >> "$AUDIT_LOG"

            printf "${GREEN}[SUCCESS] '${REMOVE_PATH}' removed from whitelist.${NC}\n"
            ;;

        3)
            print ""
            if [ -s "$WHITE_LIST" ]; then
                cat -n "$WHITE_LIST"
            else
                print "Whitelist is empty."
            fi
            ;;

        4) print "Exiting." ;;
        *) printf "${RED}[ERROR] Invalid option.${NC}\n"; return 1 ;;
    esac
    printf "%s\n" '========================================================='
}

# ── uninstall_clamav ──────────────────────────────────────────────────────────
uninstall_clamav() {
    check_root

    typeset IS_INSTALLED=0
    rpm -q clamav >/dev/null 2>&1    && IS_INSTALLED=1
    [ -f "$SETUP_COMPLETE" ]         && IS_INSTALLED=1
    [ -x "$CLAMSCAN_BIN" ]           && IS_INSTALLED=1

    if [ "$IS_INSTALLED" -eq 0 ]; then
        print "[INFO] ClamAV does not appear to be installed. Nothing to remove."
        return 0
    fi

    printf "${RED}[!] Warning: This will remove ClamAV, all logs, and automation scripts.${NC}\n"
    printf "Are you sure? (y/N): "
    read -r CONFIRM
    if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
        print "Aborted. No changes made."
        return 0
    fi

    print ""
    print "[+] Stopping any running ClamAV processes..."
    kill -9 $(ps -ef | grep '[c]lamscan' | awk '{print $2}') 2>/dev/null || true
    kill -9 $(ps -ef | grep '[f]reshclam' | awk '{print $2}') 2>/dev/null || true

    print "[+] Removing cron jobs..."
    typeset TMP_CRON
    TMP_CRON=$(mktemp /tmp/crontab_XXXXXX)
    crontab -l 2>/dev/null | grep -v "aix_clamav\|aix_freshclam\|clamav" > "$TMP_CRON"
    if [ -s "$TMP_CRON" ]; then
        crontab "$TMP_CRON"
    else
        crontab -r 2>/dev/null || true
    fi
    rm -f "$TMP_CRON"
    printf "${GREEN}[OK] Cron jobs removed.${NC}\n"

    print "[+] Removing automation scripts..."
    rm -f "$SCAN_SCRIPT" "$FRESHCLAM_SCRIPT" "$REPORT_SCRIPT"
    printf "${GREEN}[OK] Automation scripts removed.${NC}\n"

    print "[+] Removing ClamAV RPM..."
    rpm -e --nodeps clamav 2>/dev/null || true
    printf "${GREEN}[OK] RPM removal attempted.${NC}\n"

    print "[+] Removing configuration, log, and database directories..."
    rm -rf "$LOG_DIR" "$DB_DIR" /opt/freeware/etc/clamav
    printf "${GREEN}[OK] Directories removed.${NC}\n"

    print "[+] Removing ClamAV LIBPATH block from ${PROFILE_FILE}..."
    typeset TMP_PROF
    TMP_PROF=$(mktemp /tmp/profile_XXXXXX)
    awk '
        /# BEGIN ClamAV LIBPATH/ { skip=1; next }
        /# END ClamAV LIBPATH/   { skip=0; next }
        skip { next }
        { print }
    ' "$PROFILE_FILE" > "$TMP_PROF" && cp "$TMP_PROF" "$PROFILE_FILE"
    rm -f "$TMP_PROF"
    printf "${GREEN}[OK] LIBPATH block removed from ${PROFILE_FILE}${NC}\n"

    print "[+] Removing libunwind symlink..."
    rm -f "$LIBUNWIND_LINK"
    printf "${GREEN}[OK] Symlink removed.${NC}\n"

    print ""
    printf "${GREEN}[+] ClamAV uninstall complete.${NC}\n"
    print ""
    print "NOTE: ${LIBUNWIND_SO} was NOT removed."
    printf "      Remove manually if no longer needed: rm -f ${LIBUNWIND_SO}\n"
    print "NOTE: The staged files in ${CLAM_STAGING} were NOT removed."
    printf "      Remove manually if no longer needed: rm -rf ${CLAM_STAGING}\n"
}

# ── run_manual_scan ───────────────────────────────────────────────────────────
run_manual_scan() {
    check_root
    set_libpath
    print ""
    printf "Trigger an immediate scan now (incremental — same logic as daily cron).\n"
    printf "Continue? (y/N): "
    read -r _CONF
    [[ "$_CONF" != "y" && "$_CONF" != "Y" ]] && print "Aborted." && return 0
    ksh "$SCAN_SCRIPT"
}


# ── run_tests ─────────────────────────────────────────────────────────────────
run_tests() {
    typeset MODE="${1:---all}"
    typeset SELF="$0"
    typeset _PASS=0 _FAIL=0 _SKIP=0

    t_pass() { printf "${GREEN}[PASS]${NC} %s\n" "$1"; _PASS=$((_PASS+1)); }
    t_fail() { printf "${RED}[FAIL]${NC} %s — %s\n" "$1" "$2"; _FAIL=$((_FAIL+1)); }
    t_skip() { printf "${YELLOW}[SKIP]${NC} %s — %s\n" "$1" "$2"; _SKIP=$((_SKIP+1)); }
    t_section() { printf "\n${CYAN}=== %s ===${NC}\n" "$1"; }
    t_expect_rc() {
        typeset _lbl="$1" _want="$2"; shift 2
        typeset _got; "$@" >/dev/null 2>&1; _got=$?
        [ "$_got" -eq "$_want" ] && t_pass "$_lbl" || t_fail "$_lbl" "rc=$_got want=$_want"
    }
    t_output_has() {
        typeset _lbl="$1" _pat="$2"; shift 2
        typeset _out; _out=$("$@" 2>&1)
        printf '%s' "$_out" | grep -q "$_pat" && t_pass "$_lbl" || t_fail "$_lbl" "pattern '$_pat' not found"
    }

    run_pre() {
        t_section "PRE-INSTALL TESTS"

        t_section "Syntax"
        ksh -n "$SELF" 2>/dev/null && t_pass "T1.1 Syntax check" || t_fail "T1.1 Syntax check" "ksh -n failed"

        t_section "Basic options"
        t_expect_rc "T2.1 --help exits 0"    0 ksh "$SELF" --help
        t_expect_rc "T2.2 --ver exits 0"     0 ksh "$SELF" --ver
        t_expect_rc "T2.3 unknown opt exits 1" 1 ksh "$SELF" --notanoption

        t_section "Staging check"
        if [ -f "${CLAM_STAGING}/clamav-1.4.3-1.aix7.2.ppc.rpm" ]; then
            t_output_has "T3.1 --stageclamav shows PRESENT" "PRESENT" ksh "$SELF" --stageclamav
        else
            t_skip "T3.1 --stageclamav PRESENT" "staging files not on this host"
        fi
        t_output_has "T3.2 --stageclamav runs without error" "STAGING" ksh "$SELF" --stageclamav
    }

    run_post() {
        t_section "POST-INSTALL TESTS"

        t_section "Health check"
        t_output_has "T4.1 --clamavcheck shows OK" "OK" ksh "$SELF" --clamavcheck

        t_section "EICAR detection"
        printf 'X5O!P%%@AP[4\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*' > /tmp/eicar_runtests.com
        typeset _EIRC; ksh "$SELF" --scan /tmp >/dev/null 2>&1; _EIRC=$?
        rm -f /tmp/eicar_runtests.com
        [ "$_EIRC" -eq 1 ] && t_pass "T5.1 EICAR detected (rc=1)" || t_fail "T5.1 EICAR detected" "rc=$_EIRC want=1"

        t_section "Clean scan"
        typeset _TMPDIR; _TMPDIR=$(mktemp -d /tmp/clamtest_XXXXXX)
        printf "harmless test file\n" > "$_TMPDIR/clean.txt"
        t_expect_rc "T6.1 Clean scan exits 0" 0 ksh "$SELF" --scan "$_TMPDIR"
        rm -rf "$_TMPDIR"

        t_section "Whitelist"
        typeset _WLP="/tmp/wl_test_$$_clamav"
        touch "$_WLP"
        printf "1\n${_WLP}\ny\n" | ksh "$SELF" --whitelsclamav >/dev/null 2>&1
        if grep -q "^${_WLP}$" "$WHITE_LIST" 2>/dev/null; then t_pass "T7.1 Whitelist add"
        else t_fail "T7.1 Whitelist add" "$_WLP not found"; fi
        typeset _WLC; _WLC=$(grep -c "^${_WLP}$" "$WHITE_LIST" 2>/dev/null | awk '{print $1}')
        printf "1\n${_WLP}\ny\n" | ksh "$SELF" --whitelsclamav >/dev/null 2>&1
        if [ "${_WLC:-0}" -eq 1 ]; then t_pass "T7.2 Whitelist no duplicate"
        else t_fail "T7.2 Whitelist duplicate" "found $_WLC copies"; fi
        printf "2\n${_WLP}\n" | ksh "$SELF" --whitelsclamav >/dev/null 2>&1
        if ! grep -q "^${_WLP}$" "$WHITE_LIST" 2>/dev/null; then t_pass "T7.3 Whitelist remove"
        else t_fail "T7.3 Whitelist remove" "path still present"; fi
        rm -f "$_WLP"

        t_section "Cron jobs"
        if crontab -l 2>/dev/null | grep -q "aix_clamav_scan"; then t_pass "T10.1 Daily scan cron present"
        else t_fail "T10.1 Daily scan cron present" "not found in crontab"; fi
        if crontab -l 2>/dev/null | grep -q "aix_freshclam"; then t_pass "T10.2 Freshclam cron present"
        else t_fail "T10.2 Freshclam cron present" "not found in crontab"; fi
        if crontab -l 2>/dev/null | grep -q "aix_clamav_weekly"; then t_pass "T10.3 Weekly report cron present"
        else t_fail "T10.3 Weekly report cron present" "not found in crontab"; fi

        t_section "LIBPATH idempotency"
        set_libpath
        set_libpath
        typeset _LC; _LC=$(grep -c "BEGIN ClamAV LIBPATH" "$PROFILE_FILE" 2>/dev/null | awk '{print $1}')
        [ "${_LC:-0}" -eq 1 ] && t_pass "T11.1 LIBPATH not duplicated" || t_fail "T11.1 LIBPATH not duplicated" "found $_LC blocks"
    }

    case "$MODE" in
        --pre)  run_pre ;;
        --post) run_post ;;
        --all|*) run_pre; run_post ;;
    esac

    printf "\n${CYAN}════════════════════════════════════════════════════════════${NC}\n"
    printf " Results:  ${GREEN}%d passed${NC}  ${RED}%d failed${NC}  ${YELLOW}%d skipped${NC}\n" "$_PASS" "$_FAIL" "$_SKIP"
    printf "${CYAN}════════════════════════════════════════════════════════════${NC}\n\n"

    if [ "$_FAIL" -gt 0 ]; then
        printf "Usage: ksh clamav.ksh --runtests [--pre | --post | --all]\n"
        exit 1
    fi
    exit 0
}


# ── Main Dispatcher ───────────────────────────────────────────────────────────
case "$1" in
    --ver)           print_version ;;
    --help)          print_help ;;
    --stageclamav)   stage_clamav ;;
    --setupclamav)   setup_clamav ;;
    --freshclam)     run_freshclam ;;
    --clamavcheck)   clamav_health_check ;;
    --testclamav)    test_clamav_setup ;;
    --scan)          scan_directory "$2" ;;
    --manualscan)    run_manual_scan ;;
    --whitelsclamav) clamav_whitelist_file ;;
    --runtests)      run_tests "$2" ;;
    --removeclamav)  uninstall_clamav ;;
    *)
        printf "${RED}Error:${NC} Unknown option: $1\n"
        printf "${GREEN}Run 'ksh clamav.ksh --help' to learn usage${NC}\n"
        exit 1
        ;;
esac
