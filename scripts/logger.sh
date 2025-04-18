#!/usr/bin/env bash
# logger.sh: Logging utilities for ComfyUI launcher

# ANSI color codes
RESET="\033[0m"
RED="\033[1;31m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
BLUE="\033[1;34m"
MAGENTA="\033[1;35m"
CYAN="\033[1;36m"

# Log levels
DEBUG=0
INFO=1
WARN=2
ERROR=3

# Default log level (can be overridden by environment)
LOG_LEVEL=${LOG_LEVEL:-$INFO}  # Default to INFO, can be overridden with LOG_LEVEL=0 for DEBUG

# Logging functions
log_debug() {
    [[ $LOG_LEVEL -le $DEBUG ]] && echo -e "${CYAN}[DEBUG]${RESET} $*"
}

log_info() {
    [[ $LOG_LEVEL -le $INFO ]] && echo -e "${GREEN}[INFO]${RESET} $*"
}

log_warn() {
    [[ $LOG_LEVEL -le $WARN ]] && echo -e "${YELLOW}[WARN]${RESET} $*"
}

log_error() {
    [[ $LOG_LEVEL -le $ERROR ]] && echo -e "${RED}[ERROR]${RESET} $*"
}

log_section() {
    echo -e "\n${MAGENTA}===== $* =====${RESET}"
}

# Function to display a spinner for operations that take time
spin_with_message() {
    local message=$1
    local pid=$2
    local spin='/-\\|'
    local i=0
    
    while kill -0 $pid 2>/dev/null; do
        i=$(( (i+1) % 4 ))
        printf "\r${BLUE}[WAIT]${RESET} %s %c" "$message" "${spin:$i:1}"
        sleep .1
    done
    
    # Clear the spinner line
    printf "\r%-60s\r" ""
}

# Function to show progress display
display_progress() {
    local current=$1
    local total=$2
    local message=$3
    local width=30
    local percent=$((current * 100 / total))
    local completed=$((width * current / total))
    
    # Create the progress bar
    local bar=""
    for ((i=0; i<completed; i++)); do
        bar+="="
    done
    for ((i=completed; i<width; i++)); do
        bar+=" "
    done
    
    printf "\r${BLUE}[PROG]${RESET} %s [%s] %d%%" "$message" "$bar" "$percent"
}

# Function to display a successful completion message
display_success() {
    printf "\r${GREEN}[DONE]${RESET} %-60s\n" "$1"
}

# Function to display a failure message
display_failure() {
    printf "\r${RED}[FAIL]${RESET} %-60s\n" "$1"
}

# Function to display command-line options
display_options() {
    echo -e "${BLUE}Options:${RESET}"
    for option in "$@"; do
        echo -e "  $option"
    done
    echo ""
}

# Function to show URL information
display_url_info() {
    echo -e "\n${BLUE}-------------------------------------------${RESET}"
    echo -e "${GREEN}ComfyUI URL: ${RESET}http://127.0.0.1:$COMFY_PORT"
    echo -e "${BLUE}-------------------------------------------${RESET}"
}

# Function to show notices/tips
display_notices() {
    echo -e "${YELLOW}NOTE:${RESET} First time startup may take several minutes while dependencies are downloaded."
    echo -e "${YELLOW}NOTE:${RESET} Models will be downloaded automatically when selected in the UI."
    echo -e "\nTo open manually: open http://127.0.0.1:$COMFY_PORT"
}
