#!/usr/bin/env bash
# TODO: Test on Apache server
# TODO: Add check for wp-cli
_MIN_VERSION=506
_SCRIPT_VERSION="1.5"
_SCRIPT_NAME="SCAN-WP-ELEMENTOR-EA"


###########################
# Helpers
###########################
function log() {
    local _BRed='\e[1;31m'    # Red
    local _BYellow='\e[1;33m' # Yellow
    local _BBlue='\e[1;34m'   # Blue
    local _BWhite='\e[1;37m'  # White
    local _NC="\e[m"          # Color Reset
    local _message="$1"
    local _level="$2"
    local _nl="\n"
    _timestamp=$(date +%d.%m.%Y-%d:%H:%M:%S-%Z)
    case $(echo "$_level" | tr '[:upper:]' '[:lower:]') in
    "info" | "information")
        echo -ne "${_BWhite}[INFO][${_SCRIPT_NAME} ${_SCRIPT_VERSION}][${_timestamp}]: ${_message}${_NC}${_nl}"
        ;;
    "warn" | "warning")
        echo -ne "${_BYellow}[WARN][${_SCRIPT_NAME} ${_SCRIPT_VERSION}][${_timestamp}]: ${_message}${_NC}${_nl}"
        ;;
    "err" | "error")
        echo -ne "${_BRed}[ERR][${_SCRIPT_NAME} ${_SCRIPT_VERSION}][${_timestamp}]: ${_message}${_NC}${_nl}"
        ;;
    *)
        echo -ne "${_BBlue}[UNKNOWN][${_SCRIPT_NAME} ${_SCRIPT_VERSION}][${_timestamp}]: ${_message}${_NC}${_nl}"
        ;;
    esac
}
function multi_distro_install() {
    local _package="$1"
    if ! command -v "$_package" >/dev/null 2>&1; then
        log "Installing $_package" "INFO"
        # Find package manager  (apt-get, dnf, pacman, brew, port, zypper)
        if command -v apt-get >/dev/null 2>&1; then
            apt-get update >/dev/null 2>&1
            apt-get install -y "$_package" >/dev/null 2>&1
        elif command -v dnf >/dev/null 2>&1; then
            dnf install -y "$_package" >/dev/null 2>&1
        elif command -v yum >/dev/null 2>&1; then
            yum install -y "$_package" >/dev/null 2>&1
        elif command -v pacman >/dev/null 2>&1; then
            pacman -S --noconfirm "$_package" >/dev/null 
        elif command -v brew >/dev/null 2>&1; then
            brew install "$_package" >/dev/null 2>&1
        elif command -v port >/dev/null 2>&1; then
            port install "$_package" >/dev/null 2>&1
        elif command -v zypper >/dev/null 2>&1; then
            zypper install -y "$_package" >/dev/null 2>&1
        else
            log "No package manager found. Please install $_package manually for $(hostname)" "ERR"
            exit 1
        fi
    fi
}
function check_root() {
    if [[ $EUID -ne 0 ]]; then
        log "This script must be run as root" "ERR"
        exit 1
    fi
}
function check_prerequisites() {
    # check if wp-cli is installed
    if ! command -v wp >/dev/null 2>&1; then
        log "wp-cli is not installed. Please install wp-cli for $(hostname)" "ERR"
        exit 1
    fi
    multi_distro_install "curl"
    multi_distro_install "jq"
}
function find_webserver() {
    local _webserver=""
    if command -v apache2 >/dev/null 2>&1; then
        _webserver="apache2"
        scan_wp "/etc/apache2/sites-enabled/" "DocumentRoot" "$_webserver"
    fi
    if command -v /usr/local/lsws/bin/lshttpd -v >/dev/null 2>&1; then
        _webserver="openlitespeed"
        scan_wp "/usr/local/lsws/conf/vhosts/" "docRoot" "$_webserver"
    fi
    if command -v nginx -v >/dev/null 2>&1; then
        _webserver="nginx"
        scan_wp "/etc/nginx/sites-enabled/" "root" "$_webserver"
    fi
    if command -v /usr/bin/whmapi1 -v >/dev/null 2>&1; then
        _webserver="whm"
        scan_whm 
    fi
}
function scan_whm() {
        _root_dirs=""
        _root_dirs_existing=""
        for _domain in $(cat /etc/localdomains); do
            _dir=$(whmapi1 domainuserdata domain="$_domain" | grep documentroot | awk '{print $2}')
            # check if directory exists
            if [ -d "$_dir" ]; then
                _root_dirs_existing="$_root_dirs_existing $_dir"
            fi
        done
        _root_dirs_existing=$(echo "$_root_dirs_existing" | tr ' ' '\n' | sort -u)
        _root_dirs_existing_length_after=$(echo "$_root_dirs_existing" | wc -w)
        for _dir in $_root_dirs_existing; do
            scan_dir "$_dir" "whm"
        done
}
function scan_dir() {
    local _dir="$1"
    local _webserver="$2"
    if [ -f "$_dir/wp-config.php" ]; then
        cd "$_dir" || exit 1
        _plugin=$(wp --allow-root plugin list --skip-themes --format=json 2>/dev/null | jq -r '.[] | "\(.name) \(.version)"' | grep essential-addons-for-elementor)
        if [ -n "$_plugin" ]; then
            # log "- Found essential-addons-for-elementor in $_plugin" "DEBUG"
            _version=$(echo "$_plugin" | awk '{print $2}')
            _version=$(echo "$_version" | sed -E "s/\.//g")
            if [ "$_version" -lt "$_MIN_VERSION" ]; then
                _main_wp_site=$(wp --allow-root site list --skip-themes --format=json 2>/dev/null | jq -r '.[] | "\(.url) \(.name)"' | head -n 1  | awk '{print $1}')
                log "VULNERABLE | Host: $(hostname) | IP: $(curl --silent ip.rso.bg) | Dir: $_dir | essential-addons-for-elementor v$_version | URL: $_main_wp_site | Web: $_webserver" "WARN"
            fi  
        fi            
    fi
}
function scan_wp() {
    _start_dir="$1"
    _root_dir="$2"
    _webserver="$3"
    _root_dirs=""
    _root_dirs_existing=""
    # check if directory exists
    if ! [ -d "$_start_dir" ]; then
        echo "Directory $_start_dir does not exist"
        return 1
    fi
    _configs=$(find "$_start_dir" -type f -exec grep -l "$_root_dir" {} \;)
    # for each line in _configs
    for _config in $_configs; do
        _directory=$(cat "$_config" | grep -E "^\s*$_root_dir\s+" | sed -E "s/^\s*$_root_dir\s+//g" | sed -E "s/;.*//g" )
        _directory=$(echo "$_directory" | sed -E "s/\/$//g")
        _root_dirs="$_root_dirs $_directory"
    done
    # remove duplicates from _root_dirs
    _root_dirs=$(echo "$_root_dirs" | tr ' ' '\n' | sort -u | tr '\n' ' ')
    # remove directories that are not existing directories from _root_dirs
    for _dir in $_root_dirs; do
        if [ -d "$_dir" ]; then
            _root_dirs_existing="$_root_dirs_existing $_dir"
        fi
    done
    for _dir in $_root_dirs_existing; do
        scan_dir "$_dir" "$_webserver"
    done
}


###########################
# Main
###########################
check_root
check_prerequisites
find_webserver
