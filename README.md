# AEM EDS project creator – Claude skill

A Claude skill that stands up a new **AEM Edge Delivery Services** site authored with **Universal Editor**, following Adobe's tutorial at <https://www.aem.live/developer/ue-tutorial>.

## Use it

Open this repo in Claude Code (or copy the skill, see below) and run:

```
/create-aem-eds-project --repo https://github.com/acme/my-site --aem-author https://author-p12345-e67890.adobeaemcloud.com
```

If you leave out either required argument, Claude asks for it once, upfront.

| Argument | Required | Default |
|---|---|---|
| `--repo` | yes | – |
| `--aem-author` | yes | – |
| `--site-name` | no | repo name |
| `--site-title` | no | Title-cased repo name |
| `--template` | no | `xwalk` (`xcom` for Commerce) |
| `--visibility` | no | `public` (Adobe's recommendation) |
| `--admins` | no | you |
| `--dir` | no | `./<repo name>` |
| `--description` | no | generated |

## What is automated and what is not

| Step | How |
|---|---|
| Create repo from the xwalk boilerplate | automated (`gh`) |
| Point `fstab.yaml` at your AEM author and push to `main` | automated |
| Download the AEM site template | automated |
| Install AEM Code Sync and finish its wizard | guided, values pre-filled |
| Create the AEM site from the template | guided, values pre-filled |
| Give the technical account the Config Admin role | guided |
| Publish from Universal Editor | guided |
| Check code bus, preview and live URLs | automated (`verify.sh`) |

The guided steps need your GitHub and Adobe sign-ins in a browser and have no public API.

## Requirements

- [GitHub CLI](https://cli.github.com) signed in (`gh auth login`) with permission to create the repo
- `git`, `curl`, `bash`
- Access to an AEM as a Cloud Service author environment

## Install elsewhere

```bash
cp -r .claude/skills/create-aem-eds-project ~/.claude/skills/              # every project
cp -r .claude/skills/create-aem-eds-project <project>/.claude/skills/      # one project
```

## Run the scripts without Claude

```bash
S=.claude/skills/create-aem-eds-project/scripts
$S/bootstrap.sh --repo acme/my-site --aem-author https://author-p12345-e67890.adobeaemcloud.com --dry-run
$S/bootstrap.sh --repo acme/my-site --aem-author https://author-p12345-e67890.adobeaemcloud.com
$S/verify.sh    --repo acme/my-site
```
