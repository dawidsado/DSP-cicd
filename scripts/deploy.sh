#!/usr/bin/env bash
# deploy.sh - deploys objects (tables + data flow) to the target space.
# Deployment ORDER MATTERS: tables first, then the data flow (the flow depends
# on the tables). Idempotent: if an object exists -> update, otherwise -> create.
#
# Usage:
#   ./scripts/deploy.sh                 # real deployment
#   DRY_RUN=1 ./scripts/deploy.sh       # plan only, does not touch the tenant

set -euo pipefail

SPACE_TARGET="${SPACE_TARGET:-PROD}"
SECRETS_FILE="${SECRETS_FILE:-config/secrets.json}"
DSP_HOST="${DSP_HOST:-https://your-tenant.region.hcs.cloud.sap}"
DRY_RUN="${DRY_RUN:-0}"

# Deployment order: [type]:[file]:[technicalName]. Tables BEFORE the flow.
DEPLOY_ORDER=(
  "local-tables:objects/local-tables/staffing_source.json:staffing_source"
  "local-tables:objects/local-tables/Efficiency_Plan.json:Efficiency_Plan"
  "data-flows:objects/data-flows/Line_Balancing_DF.json:Line_Balancing_DF"
)

log()  { printf '>> %s\n' "$*"; }
ok()   { printf '[OK] %s\n' "$*"; }
warn() { printf '[!] %s\n' "$*"; }

command -v datasphere >/dev/null || { echo "datasphere CLI not found" >&2; exit 1; }
[[ -f "$SECRETS_FILE" ]] || { echo "secrets file not found: $SECRETS_FILE" >&2; exit 1; }

# Every call carries --host (so the CLI knows which tenant/cache to use)
# and --secrets-file (headless authentication, no interactive login).
dsp() { datasphere "$@" --host "$DSP_HOST" --secrets-file "$SECRETS_FILE"; }

# Does an object of the given type and name already exist in the target space?
exists() {
  local type="$1" name="$2" lf
  lf="$(mktemp)"
  if dsp objects "$type" list --space "$SPACE_TARGET" --select technicalName \
        --output "$lf" 2>/dev/null; then
    jq -e --arg n "$name" '.[]?|select(.technicalName==$n)' "$lf" >/dev/null 2>&1
    local rc=$?; rm -f "$lf"; return $rc
  fi
  rm -f "$lf"; return 1
}

log "Deploying to space: $SPACE_TARGET   (dry-run=$DRY_RUN)"
created=0; updated=0; failed=0

for entry in "${DEPLOY_ORDER[@]}"; do
  IFS=':' read -r type file name <<< "$entry"

  [[ -f "$file" ]] || { warn "Missing file: $file - skipping"; continue; }

  if exists "$type" "$name"; then action="update"; else action="create"; fi

  if [[ "$DRY_RUN" == "1" ]]; then
    printf '  [plan] %-7s %-12s %s\n' "$action" "$type" "$name"
    continue
  fi

  log "$action $type/$name"
  if dsp objects "$type" "$action" --space "$SPACE_TARGET" \
        --technical-name "$name" --file-path "$file"; then
    [[ "$action" == "create" ]] && created=$((created+1)) || updated=$((updated+1))
    ok "$action done: $name"
  else
    warn "FAILED ($action): $name"
    failed=$((failed+1))
  fi
done

echo
ok "Created: $created   Updated: $updated   Failed: $failed"
[[ "$failed" -gt 0 ]] && exit 1 || exit 0