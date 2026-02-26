#!/bin/sh
# backup-postgres.sh - Back up PostgreSQL to Google Cloud Storage
#
# Designed for FreeBSD on GCP. Uses the instance metadata server for
# authentication (no gcloud SDK required) and the GCS XML API for upload.
set -eu

DB_NAME="synapse"
GCS_BUCKET="__GCS_BUCKET__"  # Replaced by Ansible at deploy time
BACKUP_DIR="/var/backups/postgres"
RETENTION_DAYS=7

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
DUMP_FILE="${BACKUP_DIR}/${DB_NAME}-${TIMESTAMP}.dump"

mkdir -p "${BACKUP_DIR}"

# Dump database (custom format = compressed + supports pg_restore)
su -m postgres -c "pg_dump -Fc ${DB_NAME}" > "${DUMP_FILE}"

# Get access token from GCP instance metadata
TOKEN=$(curl -sf -H "Metadata-Flavor: Google" \
  "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")

# Upload to GCS (XML API supports up to 5 GB per PUT)
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  -X PUT \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/octet-stream" \
  -T "${DUMP_FILE}" \
  "https://storage.googleapis.com/${GCS_BUCKET}/${DB_NAME}-${TIMESTAMP}.dump")

if [ "${HTTP_CODE}" -ne 200 ]; then
  echo "$(date): ERROR: GCS upload failed (HTTP ${HTTP_CODE})" >&2
  exit 1
fi

# Remove old local backups
find "${BACKUP_DIR}" -name "${DB_NAME}-*.dump" -mtime +${RETENTION_DAYS} -delete

echo "$(date): Backup uploaded: gs://${GCS_BUCKET}/${DB_NAME}-${TIMESTAMP}.dump"
