#!/usr/bin/env bash
# Verify each stage of an AEM EDS + Universal Editor setup.
# Usage: verify.sh --repo <url|owner/name> [--aem-author <url>]
set -uo pipefail
REPO="" AEM=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="${2:-}"; shift 2 ;;
    --aem-author|--aem-url|--aem) AEM="${2:-}"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
[[ -n "$REPO" ]] || { echo "--repo is required" >&2; exit 2; }
r="${REPO%.git}"; r="${r%/}"; r="${r#git@github.com:}"; r="${r#https://github.com/}"; r="${r#github.com/}"
OWNER="${r%%/*}"; NAME="${r##*/}"; ORG_LC="$(tr '[:upper:]' '[:lower:]' <<<"$OWNER")"
PREVIEW="https://main--${NAME}--${ORG_LC}.aem.page"
LIVE="https://main--${NAME}--${ORG_LC}.aem.live"
code() { curl -s -o /dev/null -L --max-time 20 -w '%{http_code}' "$1" 2>/dev/null || echo 000; }
fail=0
check() { # label, url, hint
  local c; c="$(code "$2")"
  if [[ "$c" == 200 ]]; then echo "PASS  $1  ($2)"; else echo "FAIL  $1  HTTP $c  ($2)"; echo "      -> $3"; fail=1; fi
}

if command -v gh >/dev/null && gh auth status >/dev/null 2>&1; then
  fstab="$(gh api "repos/${OWNER}/${NAME}/contents/fstab.yaml" --jq .content 2>/dev/null | base64 -d 2>/dev/null || true)"
  if [[ -z "$fstab" ]]; then
    echo "INFO  fstab.yaml not in repo (fine once the configuration service owns the content source)"
  elif [[ "$fstab" == *"/bin/franklin.delivery/${OWNER}/${NAME}/main"* ]]; then
    echo "PASS  fstab.yaml points at this repo's franklin.delivery endpoint"
    if [[ -n "$AEM" ]]; then
      h="${AEM#https://}"; h="${h%%/*}"
      [[ "$fstab" == *"$h"* ]] || { echo "FAIL  fstab.yaml does not reference $h"; fail=1; }
    fi
  else
    echo "FAIL  fstab.yaml still has the template's content source"; echo "      -> re-run bootstrap.sh"; fail=1
  fi
fi

check "Code Sync: code bus serves the repo " "$PREVIEW/scripts/aem.js" \
  "Install https://github.com/apps/aem-code-sync on ${OWNER}/${NAME} and finish its setup wizard."
check "Preview: AEM content reaches aem.page" "$PREVIEW/" \
  "Create the AEM site, give the technical account the Config Admin role, then Publish > Preview in Universal Editor."
check "Live: content published to aem.live  " "$LIVE/" \
  "Optional for a new project: Publish > Live in Universal Editor when you are ready."
exit $fail
