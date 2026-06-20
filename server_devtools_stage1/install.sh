#!/usr/bin/env bash
set -euo pipefail

echo "DEPRECATED: server_devtools_stage1/install.sh now redirects to server_devtools_stage1_safe/install.sh"
exec bash <(curl -fsSL https://raw.githubusercontent.com/Phenolemox/Main/main/server_devtools_stage1_safe/install.sh)
