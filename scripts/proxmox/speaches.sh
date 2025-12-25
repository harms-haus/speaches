#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: Blake (harms-haus)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/harms-haus/speaches

# Source the community build functions
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)

APP="Speaches"
var_tags="${var_tags:-ai;speech}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-20}"
var_os="${var_os:-ubuntu}"
var_version="${var_version:-24.04}"
var_gpu="${var_gpu:-yes}"

# Override build_container to use our custom install script from this repository
# The community build_container function hardcodes the URL to their own repo.
# We use eval and sed to replace the URL in the function definition.
eval "$(declare -f build_container | sed 's|https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/install/${var_install}.sh|https://raw.githubusercontent.com/harms-haus/speaches/master/scripts/proxmox/speaches-install.sh|')"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/speaches ]]; then
    msg_error "No Speaches Installation Found!"
    exit
  fi

  msg_info "Updating Speaches"
  cd /opt/speaches
  git pull
  uv sync --no-dev
  systemctl restart speaches
  msg_ok "Updated successfully!"
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8000${CL}"
