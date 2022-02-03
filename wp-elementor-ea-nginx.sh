#!/usr/bin/env bash
MIN_VERSION=506
function check_prerequisites() {
    if ! command -v jq >/dev/null 2>&1; then
        echo "Installing jq"
        apt-get update >/dev/null 2>&1 &&  apt-get install -y jq >/dev/null 2>&1
    fi
}
function scan_wp() {
    for file in $(find /etc/nginx/sites-enabled/ -type f); do
        # echo  "=== Checking: $file"
        _directory=$(grep -E "^\s*root\s+" "$file" | sed -E "s/^\s*root\s+//g" | sed -E "s/;.*//g")
        if [ -f "$_directory/wp-config.php" ]; then
            # echo "- Found wp-config.php in $_directory"
            cd "$_directory" || exit 1
            _plugin=$(wp --allow-root plugin list --skip-themes --format=json 2>/dev/null | jq -r '.[] | "\(.name) \(.version)"' | grep essential-addons-for-elementor)
            if [ -n "$_plugin" ]; then
                # echo "- Found essential-addons-for-elementor in $_plugin"
                _version=$(echo "$_plugin" | awk '{print $2}')
                _version=$(echo "$_version" | sed -E "s/\.//g")
                if [ "$_version" -lt "$MIN_VERSION" ]; then
                    _main_wp_site=$(wp --allow-root site list --skip-themes --format=json 2>/dev/null | jq -r '.[] | "\(.url) \(.name)"' | head -n 1  | awk '{print $1}')
                    echo "VULNERABLE | Host: $(hostname) | IP: $(curl --silent ip.rso.bg) | Dir: $_directory | essential-addons-for-elementor v$_version | URL: $_main_wp_site"
                fi  
            fi            
        fi
    done
}

check_prerequisites
scan_wp
