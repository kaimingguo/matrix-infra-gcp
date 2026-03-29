#!/bin/sh
# backup-postgres.sh - Back up PostgreSQL to Google Cloud Storage
#
# Designed for FreeBSD on GCP. Uses the instance metadata server for
# authentication (no gcloud SDK required) and the GCS XML API for upload.
set -eu

DATABASES="synapse mautrix_telegram"
GCS_BUCKET="__GCS_BUCKET__"  # Replaced by Ansible at deploy time
BACKUP_DIR="/var/backups/postgres"
RETENTION_DAYS=7

TIMESTAMP=$(date +%Y%m%d-%H%M%S)

mkdir -p "${BACKUP_DIR}"

# Get access token from GCP instance metadata
TOKEN=$(curl -sf -H "Metadata-Flavor: Google" \
  "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")

for DB_NAME in ${DATABASES}; do
  DUMP_FILE="${BACKUP_DIR}/${DB_NAME}-${TIMESTAMP}.dump"

  # Dump database (custom format = compressed + supports pg_restore)
  su -m postgres -c "pg_dump -Fc ${DB_NAME}" > "${DUMP_FILE}" 2>/dev/null || continue

  # Upload to GCS (XML API supports up to 5 GB per PUT)
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    -X PUT \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/octet-stream" \
    -T "${DUMP_FILE}" \
    "https://storage.googleapis.com/${GCS_BUCKET}/${DB_NAME}-${TIMESTAMP}.dump")

  if [ "${HTTP_CODE}" -ne 200 ]; then
    echo "$(date): ERROR: GCS upload failed for ${DB_NAME} (HTTP ${HTTP_CODE})" >&2
  else
    echo "$(date): Backup uploaded: gs://${GCS_BUCKET}/${DB_NAME}-${TIMESTAMP}.dump"
  fi

  # Remove old local backups
  find "${BACKUP_DIR}" -name "${DB_NAME}-*.dump" -mtime +${RETENTION_DAYS} -delete
done
