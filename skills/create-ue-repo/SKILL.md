---
name: create-ue-repo
description: Create the GitHub code repo for a new AEM Edge Delivery Services site authored with Universal Editor (xwalk) and point its fstab.yaml at an AEM as a Cloud Service author, using only the GitHub API. Steps 1 and 2 of https://www.aem.live/developer/ue-tutorial. Use when asked to create or scaffold a Universal Editor / xwalk / EDS repo and the repo name and AEM author URL are given as arguments; runs unattended (no prompts, no browser, no gh CLI).
argument-hint: --repo <owner/name> --aem-author <author-url> [--template xwalk|xcom] [--visibility public|private] [--description text] [--branch main] [--dry-run]
allowed-tools: Bash(node:*), Read
---

# Create a Universal Editor (xwalk) repo — steps 1 and 2

Arguments passed to this skill: `$ARGUMENTS`

This skill does exactly two things, both through the GitHub REST API:

1. **Create the repo** from `adobe-rnd/aem-boilerplate-xwalk` (or `-xcom` for Commerce) — `POST /repos/{template}/generate`.
2. **Set the content source**: rewrite `fstab.yaml` on `main` to
   `https://<aem-author>/bin/franklin.delivery/<owner>/<repo>/main` (`type: markup`, `suffix: .html`) — `PUT /repos/{owner}/{repo}/contents/fstab.yaml`.

It does **not** install AEM Code Sync, create the AEM site, grant the technical account, or publish. Those are later steps of the tutorial.

## Arguments

| Argument | Required | Default | Notes |
|---|---|---|---|
| `--repo` | **yes** | – | `owner/name` or `https://github.com/owner/name`. Name: lowercase letters, digits, single hyphens. |
| `--aem-author` | **yes** | – | `https://author-p<program>-e<env>.adobeaemcloud.com`. A publish host is rejected. |
| `--template` | no | `xwalk` | `xcom` only for Adobe Commerce storefronts. |
| `--visibility` | no | `public` | `public` or `private`. |
| `--description` | no | generated | GitHub repo description. |
| `--branch` | no | `main` | Branch Edge Delivery reads; keep `main` unless told otherwise. |
| `--dry-run` | no | off | Validates inputs and does read-only checks; changes nothing. |

## Credentials

The script reads the token from the **`GITHUB_TOKEN`** (or `GH_TOKEN`) environment variable. Never pass a token, password or other secret as an argument, never write one into a file, and never echo it. If a token appears in `$ARGUMENTS`, stop and tell the user to set it as an environment variable instead.

Required token permissions:
- Classic PAT: `repo` (or `public_repo` for public repos only). For an org, the token must have access to that org (SSO-authorized if the org uses SSO).
- Fine-grained PAT: resource owner = the target owner; **Administration: Read and write** and **Contents: Read and write**.

## How to run

Do not ask the user any questions. Everything comes from `$ARGUMENTS`.

1. If `--repo` or `--aem-author` is missing, do not ask; report which ones are missing and the usage line from `argument-hint`, then stop.
2. Run from this skill's directory, passing the arguments through unchanged:

   ```bash
   node scripts/create-ue-repo.mjs $ARGUMENTS
   ```

   Progress goes to stderr; a single JSON object goes to stdout. Exit code `0` = success, `2` = bad arguments, `1` = anything else.
3. The command is idempotent: if the repo already exists **and** is an xwalk project (has `component-definition.json`), it is reused and only `fstab.yaml` is updated if needed. An existing repo that is not an xwalk project is never modified.

## Reporting

Report from the JSON result, in a few lines:
- `ok`, `repo_url`, `steps.create_repo` (`created` | `reused-existing`), `steps.fstab` (`committed` | `already-up-to-date`), `fstab_commit`
- `content_source_url` and `preview_url` — needed for the next tutorial steps.

On failure, relay `error` verbatim. Common causes:
- `GITHUB_TOKEN was rejected` / `HTTP 403` / `HTTP 404` on create → the token lacks the scopes above or access to the org.
- `HTTP 422 ... name already exists` → the name is taken in that owner by a repo the token cannot read.
- `template files did not appear within 60s` → re-run the same command.

## Next steps (not done by this skill)

Mention briefly that the tutorial continues with: install AEM Code Sync on the repo (`https://github.com/apps/aem-code-sync`), create the AEM site from the template at `PROJECT_URL = preview_url`, give the technical account Config Admin, and publish to preview. `fstab.yaml` must stay on `main` until Code Sync has registered the site.
