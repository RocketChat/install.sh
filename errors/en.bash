#!/usr/bin/env bash

source "../b-log/b-log.sh"

show_short_help() {
  NOTICE "Run '$(basename "$0") -h' to see the full list of available options."
}

print_run_as_root_error_and_exit() {
  ERROR "This script must be run as root. Cancelling"
  show_short_help
  exit 1
}

print_input_from_pipe_error_and_exit() {
  ERROR "This script is interactive, it can't be run with stdin piped"
  exit 1
}

print_incorrect_parameters_error_and_exit() {
  ERROR "Incorrect parameters passed. Select one option."
  INFO -e ""
  show_help
  exit 2
}

error_with_no_value_specified() {
  WARN "Command line option: '--${1}' must have an assigned value."
  show_short_help
}

print_distro_not_supported_error_and_exit() {
  ERROR "The detected Linux distribution ${1} is not supported by rocketchatctl."
  exit 1
}

print_distro_version_not_supported_error_and_exit() {
  FATAL "${1} version ${2} is not supported by rocketchatctl."
  exit 1
}

print_mongo_version_not_supported_and_exit() {
  ERROR "The detected Linux distribution does not support choosing mongo version."
  exit 1
}

print_check_mongo_storage_and_exit() {
  ERROR "IMPORTANT: Starting with Rocket.Chat version 4.X, a \"wiredTiger\" storage engine is required in MongoDB. Please migrate your existing database first: https://docs.rocket.chat/installation/manual-installation/mongodb-mmap-to-wiredtiger-migration"
  exit 1
}

print_node_version_error_and_exit() {
  ERROR "Different nodejs version already exists in the system. Cancelling"
  exit 1
}

print_use_mongo_for_rocketchat_error_and_exit() {
  ERROR "mongod already exists in the system. Cancelling"
  exit 1
}

print_mongo_storage_engine_error_and_exit() {
  ERROR "Storage engine from previous mongo installation in your system is not wiredTiger. Cancelling"
  exit 1
}
print_mongo_connection_failed_error_and_exit() {
  ERROR "Connection failed to previous installed mongo in your system. Cancelling"
  exit 1
}

print_rocketchat_installed_error_and_exit() {
  ERROR "RocketChat server already installed. Cancelling"
  exit 1
}

print_root_url_error_and_exit() {
  ERROR "root-url must have an assigned value. Use --root-url=<URL> for unattended install or the configure option. Cancelling"
  show_short_help
  exit 2
}

print_wrong_webserver_error_and_set_none() {
  ERROR "webserver assigned value should be traefik, caddy or none. Use --webserver=(traefik/caddy/none) for unattended install. Skipping webserver installation"
  INFO -e ""
}

print_email_error_and_exit() {
  ERROR "letsencrypt-email must have an assigned value if decided to install a webserver or use configure option. Cancelling"
  show_short_help
  exit 2
}

print_check_updates_error_and_exit() {
  ERROR "Could not determine if updates available for RocketChat server."
  exit 1
}

print_update_install_failed_error_and_exit() {
  ERROR "Something went wrong backing up current RocketChat server version before update. Cancelling"
  exit 1
}

print_upgrade_download_rocketchatctl_error_and_exit() {
  ERROR "Error downloading rocketchatctl. Cancelling"
  exit 1
}

print_update_install_failed_exit() {
  ERROR "Error in updated RocketChat server health check, restoring backup."
  exit 1
}

print_update_backup_failed_exit() {
  ERROR "Update failed, can't get RocketChat server API in port $PORT. Cancelling"
  exit 1
}

print_download_traefik_error_and_exit() {
  ERROR "Error downloading traefik. Cancelling"
  exit 1
}

print_rocketchat_not_running_error_and_exit() {
  ERROR "RocketChat server not running. Cancelling"
  exit 1
}

print_rocketchat_in_latest_version_and_exit() {
  ERROR "RocketChat server already in latest version."
  exit 2
}

print_no_webserver_installed_and_exit() {
  ERROR "Looks like you don't have either Caddy or Traefik installed."
  exit 2
}

print_make_backup() {
  INFO "Updates could be risky, you can use the backup option # rocketchatctl backup, to create a backup of the rocketchat database first. Please check that you have enough space in your system to store the backup."
}

print_check_update_change_node_version() {
  INFO "IMPORTANT: Update from version 2.x to 3.x requires node update, if you decide to update, your node version will change from 8.x to 12.x."
}

print_update_available_and_exit() {
  INFO "Current update available for RocketChat server: from $current_rocketchat_version to $latest_rocketchat_version."
}

print_backup_ok() {
  INFO "Backup done successfully, check for the backup file in $backup_dir/dump_$sufix.gz. You can restore using # mongorestore --host localhost:27017 --db rocketchat --archive --gzip < $backup_dir/dump_$sufix.gz"
}

print_backup_dir_error_and_exit() {
  ERROR "Can't write in the backup directory: $backup_dir"
  exit 1
}

print_node_not_updated_error_and_exit() {
  ERROR "Error: node version was not updated correctly. Cancelling ..."
  exit 1
}

print_no_release_information_file_found_error() {
  FATAL "could't find /etc/os-release file; can't check for host compatibility"
  exit 1
}

print_done() {
  INFO "Done :)"
}
