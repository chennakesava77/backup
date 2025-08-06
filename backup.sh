#!/bin/bash

# Load config if it exists
[ -f ./config.sh ] && source ./config.sh

# === Default values ===
LOG_FILE="./backup.log"
TIMESTAMP=$(date '+%Y-%m-%d_%H-%M-%S')
BACKUP_DIR="$HOME/backups/$TIMESTAMP"
mkdir -p "$BACKUP_DIR"

COMPRESS=false
REMOTE=false
NO_LOG=false
RECENT_MODE=false
RECENT_DURATION=""
FILES=()
MAX_BACKUPS=5

# === Help menu ===
show_help() {
  cat << EOF
Usage: ./backup.sh [OPTIONS] [FILES]

Options:
  --compress           Compress backup into a .tar.gz archive
  --remote             Upload backup to remote server (set in config.sh)
  --recent [Xd/Xh]     Backup files modified in last X days/hours
  --no-log             Disable logging
  --help               Show this help menu

Examples:
  ./backup.sh file1.txt file2.pdf
  ./backup.sh --compress file.txt
  ./backup.sh --recent 1d
  ./backup.sh --remote file.txt
EOF
}

# === Parse arguments ===
while [[ "$1" != "" ]]; do
  case $1 in
    --compress ) COMPRESS=true ;;
    --remote ) REMOTE=true ;;
    --no-log ) NO_LOG=true ;;
    --recent )
      RECENT_MODE=true
      shift
      RECENT_DURATION="$1"
      ;;
    --help ) show_help; exit ;;
    * ) FILES+=("$1") ;;
  esac
  shift
done

# === Handle recent flag ===
if $RECENT_MODE; then
  if [[ "$RECENT_DURATION" == *d ]]; then
    FIND_TIME="${RECENT_DURATION%d} days ago"
  elif [[ "$RECENT_DURATION" == *h ]]; then
    FIND_TIME="${RECENT_DURATION%h} hours ago"
  else
    echo "Invalid format for --recent. Use 1d or 2h."
    exit 1
  fi

  echo " Finding files modified since $FIND_TIME..."
  FILES=($(find ~ -type f -newermt "$FIND_TIME"))
fi

# === Backup files ===
echo " Starting backup to $BACKUP_DIR"
for file in "${FILES[@]}"; do
  if [[ -f "$file" ]]; then
    cp "$file" "$BACKUP_DIR/$(basename "$file").bak"
    echo "   Backed up: $file"
    $NO_LOG || echo "$(date) - Backed up: $file" >> "$LOG_FILE"
  else
    echo "   File not found: $file"
    $NO_LOG || echo "$(date) - Failed: $file not found" >> "$LOG_FILE"
  fi
done

# === Compress if required ===
if $COMPRESS; then
  ARCHIVE_NAME="backup_$TIMESTAMP.tar.gz"
  tar -czf "$ARCHIVE_NAME" -C "$BACKUP_DIR" .
  echo "  Compressed backup to $ARCHIVE_NAME"
  $NO_LOG || echo "$(date) - Compressed to $ARCHIVE_NAME" >> "$LOG_FILE"
fi

# === Upload to remote server ===
if $REMOTE; then
  if [[ -z "$REMOTE_USER" || -z "$REMOTE_HOST" || -z "$REMOTE_PATH" ]]; then
    echo "❗ Remote config missing. Please set REMOTE_USER, REMOTE_HOST, REMOTE_PATH in config.sh"
    exit 1
  fi

  FILE_TO_SEND="$BACKUP_DIR"
  [[ $COMPRESS == true ]] && FILE_TO_SEND="$ARCHIVE_NAME"

  echo " Uploading to ${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PATH} ..."
  scp -r "$FILE_TO_SEND" "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PATH}"

  if [[ $? -eq 0 ]]; then
    echo " Remote upload complete"
    $NO_LOG || echo "$(date) - Remote upload completed" >> "$LOG_FILE"
  else
    echo " Remote upload failed"
    $NO_LOG || echo "$(date) - Remote upload failed" >> "$LOG_FILE"
  fi
fi

# === Backup rotation ===
cd "$HOME/backups"
backup_folders=( $(ls -dt */ 2>/dev/null) )
if (( ${#backup_folders[@]} > MAX_BACKUPS )); then
  for folder in "${backup_folders[@]:$MAX_BACKUPS}"; do
    rm -rf "$folder"
    echo " Deleted old backup: $folder"
    $NO_LOG || echo "$(date) - Deleted old backup: $folder" >> "$LOG_FILE"
  done
fi

echo " Backup completed successfully."
