#!/usr/bin/env bash
# Bootstrap an AEM Edge Delivery Services + Universal Editor (xwalk) project.
# Automates the scriptable half of https://www.aem.live/developer/ue-tutorial:
#   create repo from template -> point fstab.yaml at AEM author -> push -> fetch AEM site template.
# Safe to re-run: every step checks whether it is already done.
set -euo pipefail

REPO="" AEM="" SITE_NAME="" SITE_TITLE="" TEMPLATE="xwalk" VISIBILITY="public"
DESCRIPTION="" DIR="" ADMINS="" DRY_RUN=0 SKIP_CLONE=0

usage() {
  cat <<USAGE
Usage: bootstrap.sh --repo <github-url|owner/name> --aem-author <author-url> [options]

Required:
  --repo <url|owner/name>   New GitHub repo to create (must not contain other code)
  --aem-author <url>        AEM as a Cloud Service AUTHOR url (author-pXXXX-eYYYY.adobeaemcloud.com)

Optional (defaults follow aem.live guidance):
  --site-name <name>        AEM site node name under /content      (default: repo name)
  --site-title <title>      AEM site title                         (default: Title Cased repo name)
  --template <xwalk|xcom>   xwalk = Sites, xcom = Commerce         (default: xwalk)
  --visibility <public|private|internal>                           (default: public)
  --description <text>      GitHub repo description
  --dir <path>              Local clone directory                  (default: ./<repo name>)
  --admins <a@x.com,b@x.com> Site config admins (shown in the checklist)
  --skip-clone              Edit fstab.yaml through the GitHub API, no local clone
  --dry-run                 Validate and print the plan; change nothing
USAGE
}

die()  { echo "ERROR: $*" >&2; exit 1; }
step() { echo; echo "==> $*"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="${2:-}"; shift 2 ;;
    --aem-author|--aem-url|--aem) AEM="${2:-}"; shift 2 ;;
    --site-name) SITE_NAME="${2:-}"; shift 2 ;;
    --site-title) SITE_TITLE="${2:-}"; shift 2 ;;
    --template) TEMPLATE="${2:-}"; shift 2 ;;
    --visibility) VISIBILITY="${2:-}"; shift 2 ;;
    --description) DESCRIPTION="${2:-}"; shift 2 ;;
    --dir) DIR="${2:-}"; shift 2 ;;
    --admins) ADMINS="${2:-}"; shift 2 ;;
    --skip-clone) SKIP_CLONE=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "unknown argument: $1" ;;
  esac
done

[[ -n "$REPO" ]] || { usage >&2; die "--repo is required"; }
[[ -n "$AEM"  ]] || { usage >&2; die "--aem-author is required"; }

# ---- normalise --repo (https url, ssh url or owner/name) ---------------------
r="${REPO%.git}"; r="${r%/}"
r="${r#git@github.com:}"; r="${r#https://github.com/}"; r="${r#http://github.com/}"; r="${r#github.com/}"
[[ "$r" =~ ^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$ ]] || die "--repo must be a github.com URL or owner/name, got: $REPO"
OWNER="${r%%/*}"; NAME="${r##*/}"
ORG_LC="$(tr '[:upper:]' '[:lower:]' <<<"$OWNER")"

# The repo name becomes part of the hostname main--<repo>--<owner>.aem.page
[[ "$NAME" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]] || die "repo name '$NAME' must be lowercase letters, digits and single hyphens (it becomes part of the aem.page hostname)"
[[ "$NAME" != *--* && "$ORG_LC" != *--* ]] || die "owner/repo must not contain '--' (reserved separator in aem.page hostnames)"
HOST_LABEL="main--${NAME}--${ORG_LC}"
(( ${#HOST_LABEL} <= 63 )) || die "'$HOST_LABEL' is ${#HOST_LABEL} chars; DNS labels max out at 63. Use a shorter repo name."

# ---- normalise --aem-author ---------------------------------------------------
a="${AEM#https://}"; a="${a#http://}"; a="${a%%/*}"; a="$(tr '[:upper:]' '[:lower:]' <<<"$a")"
if [[ "$a" =~ ^publish-p[0-9]+-e[0-9]+\.adobeaemcloud\.com$ ]]; then
  die "'$a' is a PUBLISH host. Edge Delivery needs the AUTHOR host: ${a/publish-/author-}"
fi
[[ "$a" =~ ^author-p[0-9]+-e[0-9]+\.adobeaemcloud\.com$ ]] || die "--aem-author must look like https://author-p12345-e67890.adobeaemcloud.com, got: $AEM"
AEM_HOST="$a"

# ---- defaults -----------------------------------------------------------------
case "$TEMPLATE" in
  xwalk) TEMPLATE_REPO="adobe-rnd/aem-boilerplate-xwalk" ;;
  xcom)  TEMPLATE_REPO="adobe-rnd/aem-boilerplate-xcom" ;;
  *) die "--template must be xwalk or xcom" ;;
esac
case "$VISIBILITY" in public|private|internal) ;; *) die "--visibility must be public, private or internal" ;; esac
SITE_NAME="${SITE_NAME:-$NAME}"
[[ "$SITE_NAME" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]] || die "--site-name must be lowercase letters, digits and hyphens"
if [[ -z "$SITE_TITLE" ]]; then
  SITE_TITLE="$(sed -E 's/-+/ /g; s/(^| )([a-z])/\1\u\2/g' <<<"$NAME")"
fi
DESCRIPTION="${DESCRIPTION:-$SITE_TITLE - AEM Edge Delivery Services site authored with Universal Editor}"
DIR="${DIR:-./$NAME}"

MOUNT_URL="https://${AEM_HOST}/bin/franklin.delivery/${OWNER}/${NAME}/main"
PREVIEW_URL="https://main--${NAME}--${ORG_LC}.aem.page"
LIVE_URL="https://main--${NAME}--${ORG_LC}.aem.live"
TEMPLATE_DIR="$(dirname "$DIR")/${NAME}-aem-site-template"

print_summary() {
  cat <<SUMMARY

---------------- RESOLVED CONFIGURATION ----------------
GITHUB_REPO=https://github.com/${OWNER}/${NAME}
GITHUB_OWNER=${OWNER}
GITHUB_REPO_NAME=${NAME}
VISIBILITY=${VISIBILITY}
TEMPLATE_REPO=${TEMPLATE_REPO}
AEM_AUTHOR=https://${AEM_HOST}
CONTENT_SOURCE_URL=${MOUNT_URL}
SITE_NAME=${SITE_NAME}
SITE_TITLE=${SITE_TITLE}
PROJECT_URL=${PREVIEW_URL}
PREVIEW_URL=${PREVIEW_URL}
LIVE_URL=${LIVE_URL}
LOCAL_DIR=${DIR}
SITE_TEMPLATE_DIR=${TEMPLATE_DIR}
ADMINS=${ADMINS:-<current user>}
--------------------------------------------------------
SUMMARY
}

if (( DRY_RUN )); then
  print_summary
  echo "Dry run: nothing was changed."
  exit 0
fi

# ---- preflight ----------------------------------------------------------------
step "Preflight"
command -v gh  >/dev/null || die "GitHub CLI (gh) is required: https://cli.github.com"
command -v git >/dev/null || die "git is required"
gh auth status >/dev/null 2>&1 || die "gh is not authenticated. Run: gh auth login"
echo "gh authenticated as $(gh api user --jq .login)"

FSTAB=$'mountpoints:\n  /:\n    url: "'"$MOUNT_URL"$'"\n    type: "markup"\n    suffix: ".html"\n'

# ---- 1. repo from template ----------------------------------------------------
step "1/4 GitHub repository ${OWNER}/${NAME}"
if gh repo view "${OWNER}/${NAME}" >/dev/null 2>&1; then
  echo "Repository already exists - reusing it."
  gh api "repos/${OWNER}/${NAME}/contents/component-definition.json" >/dev/null 2>&1 \
    || die "Existing repo does not look like an xwalk boilerplate project (no component-definition.json). Refusing to modify it."
else
  gh repo create "${OWNER}/${NAME}" --template "$TEMPLATE_REPO" "--${VISIBILITY}" --description "$DESCRIPTION"
  echo "Created from template ${TEMPLATE_REPO}."
fi
# Template contents are copied asynchronously - wait for them.
for i in $(seq 1 30); do
  gh api "repos/${OWNER}/${NAME}/contents/scripts/aem.js" >/dev/null 2>&1 && break
  (( i == 30 )) && die "Template files did not appear after 60s. Re-run this script."
  sleep 2
done

# ---- 2. content source --------------------------------------------------------
step "2/4 Point fstab.yaml at ${AEM_HOST}"
if (( SKIP_CLONE )); then
  current="$(gh api "repos/${OWNER}/${NAME}/contents/fstab.yaml" --jq .content 2>/dev/null | base64 -d 2>/dev/null || true)"
  if [[ "$current" == *"$MOUNT_URL"* ]]; then
    echo "fstab.yaml already up to date."
  else
    sha="$(gh api "repos/${OWNER}/${NAME}/contents/fstab.yaml" --jq .sha 2>/dev/null || true)"
    gh api -X PUT "repos/${OWNER}/${NAME}/contents/fstab.yaml" \
      -f message="chore: point content source at AEM author" \
      -f content="$(printf '%s' "$FSTAB" | base64 | tr -d '\n')" \
      -f branch=main ${sha:+-f sha="$sha"} >/dev/null
    echo "fstab.yaml committed to main via API."
  fi
else
  if [[ -d "$DIR/.git" ]]; then
    git -C "$DIR" pull -q --ff-only origin main
  else
    gh repo clone "${OWNER}/${NAME}" "$DIR" -- -q
  fi
  printf '%s' "$FSTAB" > "$DIR/fstab.yaml"
  # Older boilerplate releases ship paths.json; newer ones map paths in the config service.
  if [[ -f "$DIR/paths.json" ]]; then
    sed -i.bak -E "s#/content/aem-boilerplate(-xcom)?/#/content/${SITE_NAME}/#g" "$DIR/paths.json" && rm -f "$DIR/paths.json.bak"
  fi
  if [[ -n "$(git -C "$DIR" status --porcelain)" ]]; then
    git -C "$DIR" add -A
    git -C "$DIR" commit -q --no-verify -m "chore: point content source at AEM author"
    git -C "$DIR" push -q origin HEAD:main
    echo "Committed and pushed to main."
  else
    echo "Content source already up to date."
  fi
fi

# ---- 3. AEM site template -----------------------------------------------------
step "3/4 Download AEM site template (latest ${TEMPLATE_REPO} release)"
mkdir -p "$TEMPLATE_DIR"
if gh release download --repo "$TEMPLATE_REPO" --pattern '*.zip' --dir "$TEMPLATE_DIR" --clobber 2>/dev/null; then
  ls -1 "$TEMPLATE_DIR"
else
  echo "WARN: could not download automatically. Get the .zip from https://github.com/${TEMPLATE_REPO}/releases"
fi

# ---- 4. summary ---------------------------------------------------------------
step "4/4 Done"
print_summary
echo "NEXT: install AEM Code Sync, create the AEM site, grant the technical account, publish."
