#!/bin/bash -e

# Usage: ./create_db_config.sh action [TARGET_USER [TARGET_PASS TARGET_PGHOST TARGET_PORT TARGET_PGDB]]

ACTION=$1

# Parameters are optional for the 'switch' action
if [ "$ACTION" != "switch" ]; then
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

# Use the STAGE environment variable
STAGE=${STAGE:-"default_stage"}

# Function to extract the pool value
extract_pool_value() {
  grep "pool:" "$CONFIG_PATH" | awk '{print $2}'
}

# Backup the original file if it doesn't exist
backup_original() {
  if [ -f "$BACKUP_PATH" ]; then
    echo "Backup file already exists, indicating a subsequent run. We are not proceeding with backup."
  else
    cp "$CONFIG_PATH" "$BACKUP_PATH"
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
}

# Revert to original configuration
revert_config() {
  if [ -f "$BACKUP_PATH" ]; then
    cp "$BACKUP_PATH" "$CONFIG_PATH"
    restart_server
    echo "Configuration reverted and server restart signal sent."
  else
    echo "Backup file not found. Cannot revert."
    exit 1
  fi
}

# Switch to migration configuration
switch_config() {
  if [ -z "$TARGET_USER" ]; then
    echo "Application name (TARGET_USER) is required for the switch action."
    exit 1
  fi

  if [ -f "$MIGRATION_PATH" ]; then
    cp "$MIGRATION_PATH" "$CONFIG_PATH"
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
}

# Main logic
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
  *)
    echo "Invalid action: $ACTION"
    echo "Usage: $0 [write|revert|switch] [TARGET_USER [TARGET_PASS TARGET_PGHOST TARGET_PORT TARGET_PGDB]]"
    exit 1
    ;;
esac
