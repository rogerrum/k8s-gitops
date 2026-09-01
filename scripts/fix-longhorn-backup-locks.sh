#!/usr/bin/env bash
# fix-longhorn-backup-locks.sh
#
# Find and delete stale Longhorn backup CRs that hold S3 locks,
# causing "failed to acquire lock" errors in VolumeSnapshots.
#
# Stale backups are identified as those NOT in Completed/InProgress/Pending state,
# OR those with no snapshot source (empty snapshotName column).
#
# Usage:
#   ./scripts/fix-longhorn-backup-locks.sh           # dry-run (default, safe)
#   ./scripts/fix-longhorn-backup-locks.sh --delete  # actually delete stale CRs

set -euo pipefail

DRY_RUN=true
NAMESPACE="longhorn-system"

for arg in "$@"; do
  case "$arg" in
    --delete) DRY_RUN=false ;;
    --dry-run) DRY_RUN=true ;;
    -h|--help)
      echo "Usage: $0 [--dry-run|--delete]"
      echo "  --dry-run  Show stale backups without deleting (default)"
      echo "  --delete   Delete stale backup CRs to release S3 locks"
      exit 0
      ;;
  esac
done

echo "=== Longhorn Stale Backup Lock Finder ==="
echo "Namespace : $NAMESPACE"
echo "Mode      : $([ "$DRY_RUN" = true ] && echo 'DRY RUN (use --delete to remove)' || echo 'DELETE')"
echo ""

# Get all backup CRs with their state
BACKUPS=$(kubectl get backup -n "$NAMESPACE" --no-headers -o custom-columns=\
"NAME:.metadata.name,\
STATE:.status.state,\
SNAPSHOT:.status.snapshotName,\
CREATED:.metadata.creationTimestamp" 2>/dev/null)

if [ -z "$BACKUPS" ]; then
  echo "No backup CRs found in $NAMESPACE."
  exit 0
fi

STALE=()

while IFS= read -r line; do
  NAME=$(echo "$line" | awk '{print $1}')
  STATE=$(echo "$line" | awk '{print $2}')
  SNAPSHOT=$(echo "$line" | awk '{print $3}')

  # Stale if: state is Error, empty/unknown, or no snapshot source
  if [[ "$STATE" == "Error" || "$STATE" == "<none>" || "$STATE" == "" || "$SNAPSHOT" == "<none>" || "$SNAPSHOT" == "" ]]; then
    STALE+=("$NAME")
    echo "  STALE  $NAME  state=$STATE  snapshot=$SNAPSHOT"
  fi
done <<< "$BACKUPS"

echo ""
echo "Found ${#STALE[@]} stale backup CR(s)."

if [ ${#STALE[@]} -eq 0 ]; then
  echo "Nothing to do."
  exit 0
fi

if [ "$DRY_RUN" = true ]; then
  echo ""
  echo "Dry-run: no changes made. Run with --delete to remove them."
  exit 0
fi

echo ""
echo "Deleting stale backup CRs..."
for NAME in "${STALE[@]}"; do
  echo "  Deleting $NAME ..."
  kubectl delete backup "$NAME" -n "$NAMESPACE"
done

echo ""
echo "Done. ${#STALE[@]} stale backup CR(s) deleted."
echo ""
echo "Tip: If VolumeSnapshots were stuck, delete the stuck kopiasnap CRs to trigger retry:"
echo "  kubectl get kopiasnap --all-namespaces | grep -v 'Succeeded\|adopted'"
