#!/usr/bin/env bash
# deploy.sh — wdraża 3 obiekty (2 tabele + data flow) do przestrzeni docelowej.
# Kolejność MA ZNACZENIE: najpierw tabele, potem flow (flow zależy od tabel).
# Idempotentne: jeśli obiekt istnieje -> update, jeśli nie -> create.
#
# Użycie:
#   ./scripts/deploy.sh                 # realne wdrożenie
#   DRY_RUN=1 ./scripts/deploy.sh       # tylko plan, nic nie dotyka tenanta

set -euo pipefail

echo "=== DIAGNOSTYKA ==="
echo "Node: $(node --version 2>/dev/null || echo BRAK)"
echo "CLI:  $(datasphere --version 2>/dev/null || echo BRAK)"
echo "Komendy CLI:"; datasphere --help 2>&1 | grep -iE "objects|spaces|tasks" || echo "  nie znaleziono objects w help"
echo "=== KONIEC DIAGNOSTYKI ==="

SPACE_TARGET="${SPACE_TARGET:-SADOWDA}"
SECRETS_FILE="${SECRETS_FILE:-config/secrets.json}"
DRY_RUN="${DRY_RUN:-0}"

# Kolejność wdrażania: [typ]:[plik]. Tabele PRZED flow.
DEPLOY_ORDER=(
  "local-tables:objects/local-tables/Efficiency_overview_vol2.json:Efficiency_overview_vol2"
  "local-tables:objects/local-tables/Prod_Efficiency_Plan.json:Prod_Efficiency_Plan"
  "data-flows:objects/data-flows/Production_Efficiency_Optimize.json:Production_Efficiency_Optimize"
)

log()  { printf '\033[1;34m▶ %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m✔ %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m! %s\033[0m\n' "$*"; }

command -v datasphere >/dev/null || { echo "Brak CLI datasphere" >&2; exit 1; }
[[ -f "$SECRETS_FILE" ]] || { echo "Brak secrets-file: $SECRETS_FILE" >&2; exit 1; }

dsp() { datasphere "$@" --secrets-file "$SECRETS_FILE"; }

# Czy obiekt danego typu i nazwy już istnieje w przestrzeni docelowej?
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

log "Wdrażam do przestrzeni: $SPACE_TARGET   (dry-run=$DRY_RUN)"
created=0; updated=0; failed=0

for entry in "${DEPLOY_ORDER[@]}"; do
  IFS=':' read -r type file name <<< "$entry"

  [[ -f "$file" ]] || { warn "Brak pliku: $file — pomijam"; continue; }

  if exists "$type" "$name"; then action="update"; else action="create"; fi

  if [[ "$DRY_RUN" == "1" ]]; then
    printf '  [plan] %-7s %-12s %s\n' "$action" "$type" "$name"
    continue
  fi

  log "$action $type/$name"
  if dsp objects "$type" "$action" --space "$SPACE_TARGET" \
        --technical-name "$name" --file-path "$file"; then
    [[ "$action" == "create" ]] && created=$((created+1)) || updated=$((updated+1))
    ok "$action OK: $name"
  else
    warn "BŁĄD ($action): $name"
    failed=$((failed+1))
  fi
done

echo
ok "Utworzono: $created   Zaktualizowano: $updated   Błędy: $failed"
[[ "$failed" -gt 0 ]] && exit 1 || exit 0
