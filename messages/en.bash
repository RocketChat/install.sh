#!/usr/bin/env bash

_source "b-log/b-log.sh"

show_long_help() {
  cat << EOM
rocketchatctl command line tool to install and update RocketChat server
Usage: $(basename "$0") [options] [--root-url=ROOT_URL --port=PORT --letsencrypt-email=EMAIL --webserver=WEBSERVER  --version=VERSION --install-node --use-mongo]
Installs node, mongo, RocketChat server and optionally a webserver (Caddy or Traefik), sets up directories and permissions to use Let's Encrypt certificates.
In case node or mongo already installed, it uses already installed versions though confirmation is required.
For node it set $NODE_VERSION as default in your system, for mongo wiredTiger storage engine and no authentication enabled is required during installation.
If you wish this script to run unattended, provide extra flags to the install option, server URL is required (--root-url).
OPTIONS
  -h help                   Display this message
  install                   Install latest RocketChat server version
  update                    Update RocketChat server from current version to latest version
  check-updates             Check for updates of RocketChat server
  upgrade-rocketchatctl     Upgrade the rocketchatctl command line tool
  configure                 Configures RocketChat server and Let's Encrypt
  backup                    Makes a rocketchat database backup
FOR UNATTENDED INSTALLATION
  --root-url=ROOT_URL       the public URL where RocketChat server will be accessible on the Internet (REQUIRED)
  --port=PORT               port for the RocketChat server, default value 3000
  --webserver=WEBSERVER     webserver to install as reverse proxy for RocketChat server, options are caddy/traefik/none (REQUIRED)
  --letsencrypt-email=EMAIL e-mail address to use for SSL certificates (REQUIRED if webserver is not none)
  --version=VERSION         RocketChat server version to install, default latest
  --install-node            in case node installed, sets node to RocketChat server recommended version, default behavoir cancel RocketChat server installation
  --use-mongo               in case mongo installed, and storage engine configured is wiredTiger, skip mongo installation but uses systems mongo for RocketChat server database,
                            default database name rocketchat
  --mongo-version=4.x.x     mongo 4 version, default value is latest (supported only for Debian and Ubuntu)
  --bind-loopback=value     value=(true|false) set to false to prevent from bind RocketChat server to loopback interface when installing a webserver (default true)
  --reg-token=TOKEN         This value can be obtained from https://cloud.rocket.chat to automatically register your workspace during startup
FOR CONFIGURE OPTION
  --rocketchat --root-url=ROOT_URL --port=PORT --bind-loopback=value                  Reconfigures RocketChat server Site-URL and port (--root-url REQUIRED)
  --lets-encrypt --root-url=ROOT_URL --letsencrypt-email=EMAIL --bind-loopback=value  Reconfigures webserver with Let's Encrypt and RocketChat server Site-URL (--root-url and letsencrypt-email REQUIRED)
FOR BACKUP OPTION
  --backup-dir=<path_to_dir>       sets the directory for storing the backup files, default backup directory is /tmp
EOM
}

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

print_is_utility_use() {
  INFO "Usage: is <key> in <array>"
}

print_wrong_is_utility_usage() {
  ERROR "incorrect use of \"is\"; unknown key ${1}"
  print
}

print_unknown_command_argument() {
  ERROR "unknown argument ${0}"
  show_long_help
  exit 1
}
