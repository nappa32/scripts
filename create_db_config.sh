#!/bin/bash -e

# Usage: ./create_db_config.sh action [TARGET_USER [TARGET_PASS TARGET_PGHOST TARGET_PORT TARGET_PGDB]]

# Redirect all output to a log file
LOG_FILE="/var/log/create_db_config.log"
touch $LOG_FILE
chown deploy:deploy $LOG_FILE

exec &> >(tee -a "$LOG_FILE")

ACTION=$1

# Parameters are optional for the 'switch' action
if [ "$ACTION" != "switch" ] && [ "$ACTION" != "write_and_switch" ]; then
  TARGET_USER=$2
  TARGET_PASS=$3
  TARGET_PGHOST=$4
  TARGET_PORT=$5
  TARGET_PGDB=$6
fi

CONFIG_PATH="/var/apps/${TARGET_USER}/current/config/database.yml"
MIGRATION_PATH="${CONFIG_PATH}.migration"
BACKUP_PATH="/var/apps/${TARGET_USER}/database.yml.chef.original"
RESTART_PATH="/var/apps/${TARGET_USER}/current/tmp/restart.txt"
APACHE_CONFIG_PATH="/etc/apache2/sites-enabled/$(echo "$TARGET_USER" | sed 's/_.*//').conf"

# Use the STAGE environment variable
STAGE=$(grep "RackEnv" "$APACHE_CONFIG_PATH" | awk '{print $2}' | head -1)

# Function to extract the pool value
extract_pool_value() {
  grep "pool:" "$CONFIG_PATH" | awk '{print $2}'
}

# Backup the original file if it doesn't exist
backup_original() {
  if [ -f "$BACKUP_PATH" ]; then
    echo "Backup file already exists, indicating a subsequent run. We are not proceeding with backup."
  else
    cat "$CONFIG_PATH" >"$BACKUP_PATH"
    chown deploy:deploy "$BACKUP_PATH"
    echo "Backup of original configuration created."
  fi
}

# Backup the original file if it doesn't exist
revert_config() {
  if [ -f "$BACKUP_PATH" ]; then
    echo "Backup file already exists. I will revert to it"
    cat "$BACKUP_PATH" >"$CONFIG_PATH"
  else
    echo "Revert failed due to missing backup file!."
    exit 1
  fi
}

# Write new configuration
write_config() {
  local pool_value=$(extract_pool_value)
  cat <<EOF >"$MIGRATION_PATH"
${STAGE}:
  adapter: postgresql
  encoding: utf8
  database: ${TARGET_PGDB}
  host: ${TARGET_PGHOST}
  username: ${TARGET_USER}
  password: ${TARGET_PASS}
  port: ${TARGET_PORT:-5432}
  pool: ${pool_value}
EOF
  echo "New configuration written."
  chown deploy:deploy "$MIGRATION_PATH"
}

# Switch to migration configuration
switch_config() {
  if [ -f "$MIGRATION_PATH" ]; then
    cat "$MIGRATION_PATH" >"$CONFIG_PATH"
    restart_server
    echo "Configuration switched and server restart signal sent."
  else
    echo "Migration file not found. Cannot switch."
    exit 1
  fi
}

# Restart the server
restart_server() {
  touch "$RESTART_PATH"
  echo "Server restart signal sent."
}

# Main logic
echo "Script started with action: $ACTION"
case "$ACTION" in
write)
  if [ $# -lt 6 ]; then
    echo "Insufficient arguments for write action."
    echo "Usage: $0 write TARGET_USER TARGET_PASS TARGET_PGHOST TARGET_PORT TARGET_PGDB"
    exit 1
  fi
  backup_original
  write_config
  ;;
revert)
  if [ -z "$TARGET_USER" ]; then
    echo "Application name (TARGET_USER) is required for the revert action."
    exit 1
  fi
  revert_config
  ;;
switch)
  TARGET_USER=$2
  switch_config
  ;;
write_and_switch)
  if [ $# -lt 6 ]; then
    echo "Insufficient arguments for write_and_switch action."
    echo "Usage: $0 write_and_switch TARGET_USER TARGET_PASS TARGET_PGHOST TARGET_PORT TARGET_PGDB"
    exit 1
  fi
  backup_original
  write_config
  switch_config
  ;;
*)
  echo "Invalid action: $ACTION"
  echo "Usage: $0 [write|revert|switch|write_and_switch] [TARGET_USER [TARGET_PASS TARGET_PGHOST TARGET_PORT TARGET_PGDB]]"
  exit 1
  ;;
esac
echo "Script ended."
