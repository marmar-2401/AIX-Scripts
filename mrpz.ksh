#!/usr/bin/env ksh 

BLACK='\033[0;30m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[0;37m'
NC='\033[0m'

check_root() {
    CURRENT_UID=$(id -u)
    if [ "${CURRENT_UID}" -ne 0 ]; then
        printf "${RED}Error: This script must be run as root.${NC}\n"
        exit 1
    fi
}

check_sccadm() {
    CURRENT_UID=$(id -u)
    local SCCADMINID=$(grep "^sccadm:" /etc/passwd | awk -F : '{print $3}')

    if [ -z "$SCCADMINID" ]; then
        printf "${RED}Error: User 'sccadm' does not exist on this system.${NC}\n"
        exit 1
    fi

    if [ "${CURRENT_UID}" -ne "${SCCADMINID}" ]; then
        printf "${RED}Error: This script must be run as sccadm.${NC}\n"
        exit 1
    fi
}

confirm_action() {
    printf "Are you sure you want to continue? (y/n): "
    read CHOICE
    
    case "$CHOICE" in
        [yY]|[yY][eE][sS])
            return 0
            ;;
        [nN]|[nN][oO])
            exit 1
            ;;
        *)
            echo "Invalid input. Please enter 'y' or 'n'."
            confirm_action
            ;;
    esac
}

print_version() {
    printf "\n${CYAN}         ################${NC}\n"
    printf "${CYAN}         ## Ver: 1.0.0 ##${NC}\n"
    printf "${CYAN}         ################${NC}\n"
    printf "${CYAN}=====================================${NC}\n"
    printf "${CYAN} __   __   ____    _____    _____ ${NC}\n"
    printf "${CYAN}|  \_/  | |  _ \  |  __ \  |__  /     ${NC}\n"
    printf "${CYAN}| |\_/| | | |_) | | |__) |   / /   ${NC}\n"
    printf "${CYAN}| |   | | |  _ <  |  __ /   / /__   ${NC}\n"
    printf "${CYAN}|_|   |_| |_| \_\ |_|      /_____|    ${NC}\n" 
    printf "${CYAN}                                     ${NC}\n"
    printf "${CYAN}           m r p z . k s h           ${NC}\n"
    printf "${CYAN}=====================================${NC}\n"
    printf "${CYAN}\nAuthor: Mark Pierce-Zellfrow ${NC}\n"
    printf "${YELLOW}\n  Ver  |    Date   |                         Changes                                 ${NC}\n"
    printf "${YELLOW}===============================================================================${NC}\n"
    printf "${MAGENTA} 1.0.0 | 05/05/2025 | - Initial release mrpz.ksh ${NC}\n"
}

print_help() {
    printf "\n${MAGENTA}Basic syntax:${NC}\n"
    printf "${YELLOW}ksh mrpz.ksh <OPTION>${NC}\n"
    printf "\n${MAGENTA}mrpz.ksh Based Options:${NC}\n"
    printf "${YELLOW}--help${NC}\t# Gives script overview information\n\n"
    printf "${YELLOW}--ver${NC} \t# Gives script versioning related information\n\n"
    printf "\n${MAGENTA}General System Information Options:${NC}\n"
    printf "${YELLOW}--clamavcheck${NC}\t# Gives you status of clamav\n\n"
    printf "${YELLOW}--testclamav${NC}\t# Makes sure clamav is configured correctly scanning\n\n"
    printf "\n"
    exit 0
}

# --- Main Logic ---

# Check if no arguments were passed
if [ $# -eq 0 ]; then
    printf "${RED}Error: No options provided.${NC}\n"
    print_help
fi

case "$1" in
    --ver) 
        print_version 
        ;;
    --help) 
        print_help 
        ;;
    *) # The missing catch-all wildcard
        printf "${RED}Error:${NC} Unknown Option Ran With Script. ${RED}Option Entered: ${NC}$1\n"
        printf "${GREEN}Run 'ksh mrpz.ksh --help' To Learn Usage ${NC} \n"
        exit 1
        ;;
esac

