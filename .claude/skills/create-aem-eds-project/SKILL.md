---
name: create-aem-eds-project
description: Create a new AEM Edge Delivery Services project authored with Universal Editor (xwalk) in a brand-new GitHub repo and connect it to an AEM as a Cloud Service author environment. Use when asked to create, scaffold, bootstrap or set up an AEM EDS / Edge Delivery / Universal Editor / xwalk / aem.live site or project.
argument-hint: --repo <github-url> --aem-author <aem-author-url> [--site-name n] [--site-title t] [--template xwalk|xcom] [--visibility public|private] [--admins a@x.com,b@x.com] [--dir path]
allowed-tools: Bash, Read, Edit, Write, AskUserQuestion, WebFetch
---

# Create an AEM EDS + Universal Editor project

Implements Adobe's tutorial <https://www.aem.live/developer/ue-tutorial> end to end.
Arguments passed to this skill: `$ARGUMENTS`

## 1. Resolve arguments (once, upfront)

| Argument | Required | Default | Notes |
|---|---|---|---|
| `--repo` | **yes** | – | GitHub URL or `owner/name` of the repo to create. Name must be lowercase letters, digits, hyphens. |
| `--aem-author` | **yes** | – | AEM Cloud **author** URL, `https://author-p<program>-e<env>.adobeaemcloud.com`. |
| `--site-name` | no | repo name | Node name under `/content` in AEM. |
| `--site-title` | no | Title-cased repo name | Shown in the AEM Sites console. |
| `--template` | no | `xwalk` | `xcom` only for Adobe Commerce storefronts. |
| `--visibility` | no | `public` | aem.live recommends public repos; use `private` only if the user says so. |
| `--admins` | no | the user's own email | Site-config admins added in the Code Sync wizard. |
| `--dir` | no | `./<repo name>` | Local clone location. |
| `--description` | no | generated | GitHub repo description. |

Rules:
- If `--repo` or `--aem-author` is missing, ask for **both missing values in one single question** before doing anything else. Never guess them.
- Never ask about optional arguments; apply the defaults silently.
- Accept loose forms (`aem-url`, a pasted AEM Sites console URL, an ssh git URL); the script normalises them.
- Run `scripts/bootstrap.sh <args> --dry-run` first. If it errors, relay the message and ask for the corrected value. Otherwise show the resolved configuration in a short table and proceed without waiting for approval, unless the target repo already exists.

## 2. Automated phase

Run from this skill's directory:

```bash
scripts/bootstrap.sh --repo <repo> --aem-author <aem> [optional args]
```

It is idempotent and does the following:
1. Creates the repo from `adobe-rnd/aem-boilerplate-xwalk` (or `-xcom`) with `gh`.
2. Rewrites `fstab.yaml` to `https://<aem-author>/bin/franklin.delivery/<owner>/<repo>/main` (`type: markup`, `suffix: .html`) and pushes to `main`. This **must** land before Code Sync is configured.
3. Updates `paths.json` to `/content/<site-name>/` if the template release still ships that file.
4. Downloads the AEM site template `.zip` from the latest boilerplate release next to the clone.

If `gh` is missing or unauthenticated, stop and tell the user to run `gh auth login`; do not fall back to creating an empty repo by other means. Add `--skip-clone` when no local checkout is wanted.

## 3. Guided phase (needs the user's browser sign-ins)

These four steps have no public API. Give the user **one** checklist with every value already filled in from the script's `RESOLVED CONFIGURATION` output. If browser-automation tools are available and the user agrees, drive the steps yourself instead; never type passwords for them.

**A. AEM Code Sync** – <https://github.com/apps/aem-code-sync> → Configure → pick the org → *Only select repositories* → the new repo → Save. In the *AEM Configuration Setup* wizard: Code → Next; Content → source type is *Other (bring your own markup)* and the URL must equal `CONTENT_SOURCE_URL` → Next; Users → add `ADMINS` as admin → Next; Save.

> If the org already had Code Sync on *All repositories*, the bot may have registered the site with the template's content source before step 2 ran. Have the user fix the Content Source URL at <https://tools.aem.live/tools/site-admin/index.html>.

**B. Create the AEM site** – on `AEM_AUTHOR`: Sites → Create → Site from template → Import the downloaded `.zip` (only once per environment) → select it → Next → Site title `SITE_TITLE`, Site name `SITE_NAME`, Project URL `PROJECT_URL` → Create.

**C. Technical account** – AEM: Tools → Cloud Services → Edge Delivery Services Configuration → the site's config → Properties → Authentication tab → copy `<id>@techacct.adobe.com`. Then at <https://tools.aem.live/tools/user-admin/index.html>: **first confirm the user's own email is listed as Admin** (otherwise they lock themselves out), then add the technical account with role **Config Admin**. Allow 1–2 minutes.

**D. Publish** – Sites console → open the site's `index` page → Edit (Universal Editor opens) → Publish → Destination *Preview* → Publish.

## 4. Verify

After the user reports each step done (and at the end), run:

```bash
scripts/verify.sh --repo <repo> --aem-author <aem>
```

- `Code Sync` failing → step A is incomplete.
- `Preview` failing → B, C or D is incomplete; a 404 right after C usually just needs two minutes.
- `Live` failing is expected until the user publishes to *Live*.

Do not report the project as finished until `Code Sync` and `Preview` pass.

## 5. Wrap up

Report in a few lines: repo URL, preview URL, live URL, AEM site path `/content/<site-name>`, local clone path. Then mention:
- Local dev: `npm install -g @adobe/aem-cli`, then `aem up` inside the clone (serves `http://localhost:3000`).
- Once the site works, `fstab.yaml` can be deleted because the configuration service now owns the content source.
- Next: creating blocks, <https://www.aem.live/developer/universal-editor-blocks>. After editing files in `models/`, run `npm run build:json`.

## Guardrails

- Only ever write to the repo named in `--repo`. If it exists and is not an xwalk boilerplate project, stop.
- Do not change the content source of a site that is already live; it forces a full re-preview and re-publish.
- Never put tokens or passwords in arguments, files or commits.
