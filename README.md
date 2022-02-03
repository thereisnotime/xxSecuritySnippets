# xxSecuritySnippets
Collection of various security scanning and patching tools .

## Essential Addons for Elementor - 31.01.2022 
- Checks all root directories of all enabled nginx/openlitespeed/apache sites
- Verifies if directory contains wp-config.php
- Needs wp-cli and jq in order to work (autoinstalls jq if missing)

Oneliner scan:
```bash
bash <(curl -s https://raw.githubusercontent.com/thereisnotime/xxSecuritySnippets/master/wp-elementor-ea.sh)
```
