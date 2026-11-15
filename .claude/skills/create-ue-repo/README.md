# create-ue-repo

Creates the GitHub repo for an AEM Edge Delivery Services + Universal Editor (xwalk) site and points `fstab.yaml` at your AEM author. This covers steps 1 and 2 of <https://www.aem.live/developer/ue-tutorial>.

It uses only the GitHub REST API, so it needs no browser, no `gh` CLI and no git clone, and it never prompts. That makes it safe to run in unattended or agentic workflows.

## Use it in Claude Code

```
/create-ue-repo --repo acme/my-site --aem-author https://author-p12345-e67890.adobeaemcloud.com
```

## Run it without Claude

Requires Node 18 or later.

```bash
export GITHUB_TOKEN=...   # classic PAT with repo scope, or fine-grained with Administration + Contents write
node .claude/skills/create-ue-repo/scripts/create-ue-repo.mjs --repo acme/my-site --aem-author https://author-p12345-e67890.adobeaemcloud.com --dry-run
node .claude/skills/create-ue-repo/scripts/create-ue-repo.mjs --repo acme/my-site --aem-author https://author-p12345-e67890.adobeaemcloud.com
```

| Argument | Required | Default |
|---|---|---|
| `--repo` | yes | – |
| `--aem-author` | yes | – |
| `--template` | no | `xwalk` (`xcom` for Commerce) |
| `--visibility` | no | `public` |
| `--description` | no | generated |
| `--branch` | no | `main` |
| `--dry-run` | no | off |

The token is read only from `GITHUB_TOKEN` or `GH_TOKEN`. Passing a token as an argument is refused.

Output is one JSON object on stdout, for example:

```json
{
  "ok": true,
  "repo_url": "https://github.com/acme/my-site",
  "content_source_url": "https://author-p12345-e67890.adobeaemcloud.com/bin/franklin.delivery/acme/my-site/main",
  "preview_url": "https://main--my-site--acme.aem.page",
  "steps": { "create_repo": "created", "fstab": "committed" }
}
```

Exit codes: `0` success, `2` invalid arguments, `1` other errors. Re-running the command is safe.

## Install elsewhere

```bash
cp -r .claude/skills/create-ue-repo ~/.claude/skills/
```
