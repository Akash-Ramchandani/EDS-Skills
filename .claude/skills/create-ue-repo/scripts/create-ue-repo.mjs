#!/usr/bin/env node
// Steps 1 and 2 of https://www.aem.live/developer/ue-tutorial, API only:
//   1. Create a GitHub repo from the AEM Universal Editor (xwalk) boilerplate template.
//   2. Point fstab.yaml at the AEM author's franklin.delivery endpoint and commit it to main.
// No browser, no git clone, no gh CLI, no prompts. Node 18+ (built-in fetch), zero dependencies.
// Auth: GITHUB_TOKEN or GH_TOKEN environment variable. Tokens are never accepted as arguments.
// Output: progress on stderr, one JSON result object on stdout. Exit 0 = success.

const API = 'https://api.github.com';
const TEMPLATES = { xwalk: 'adobe-rnd/aem-boilerplate-xwalk', xcom: 'adobe-rnd/aem-boilerplate-xcom' };

const USAGE = `Usage: node create-ue-repo.mjs --repo <owner/name | github url> --aem-author <author url> [options]

Required:
  --repo <owner/name>        Repo to create, e.g. acme/my-site or https://github.com/acme/my-site
  --aem-author <url>         AEM Cloud author, e.g. https://author-p12345-e67890.adobeaemcloud.com

Optional:
  --template <xwalk|xcom>    xwalk = AEM Sites (default), xcom = Adobe Commerce
  --visibility <public|private>  Default public (aem.live recommendation)
  --description <text>       GitHub repo description
  --branch <name>            Branch Edge Delivery reads (default main)
  --dry-run                  Validate inputs and read-only checks; change nothing (token optional)

Environment:
  GITHUB_TOKEN or GH_TOKEN   Classic PAT with 'repo' scope (or 'public_repo' for public repos), or a
                             fine-grained PAT with Administration: write + Contents: write on the owner.`;

// ---------------------------------------------------------------- helpers
const log = (...m) => console.error(...m);
const result = { ok: false, steps: {} };
// Unwinds to the top level instead of calling process.exit(), which can crash Node on
// Windows while fetch sockets are still closing. The exit code is set via process.exitCode.
class Done extends Error {}
function finish(code, error) {
  if (error) result.error = error;
  result.ok = code === 0;
  process.stdout.write(JSON.stringify(result, null, 2) + '\n');
  process.exitCode = code;
  throw new Done();
}
const fail = (msg, code = 1) => { log(`ERROR: ${msg}`); finish(code, msg); };

function parseArgs(argv) {
  const out = {};
  const flags = new Set(['dry-run', 'help']);
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '-h') { out.help = true; continue; }
    if (!a.startsWith('--')) fail(`unexpected argument: ${a}`, 2);
    let [k, v] = a.slice(2).split(/=(.*)/s);
    if (flags.has(k)) { out[k] = true; continue; }
    if (v === undefined) { v = argv[++i]; if (v === undefined || v.startsWith('--')) fail(`--${k} needs a value`, 2); }
    out[k] = v;
  }
  return out;
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const token = process.env.GITHUB_TOKEN || process.env.GH_TOKEN || '';

async function gh(method, path, body) {
  const headers = {
    Accept: 'application/vnd.github+json',
    'X-GitHub-Api-Version': '2022-11-28',
    'User-Agent': 'create-ue-repo-skill',
  };
  if (token) headers.Authorization = `Bearer ${token}`;
  if (body) headers['Content-Type'] = 'application/json';
  const res = await fetch(API + path, { method, headers, body: body ? JSON.stringify(body) : undefined });
  const text = await res.text();
  let data; try { data = text ? JSON.parse(text) : null; } catch { data = text; }
  return { status: res.status, data };
}
const ghMsg = (r) => `HTTP ${r.status}${r.data && r.data.message ? `: ${r.data.message}` : ''}`;

async function main() {
// ---------------------------------------------------------------- inputs
const args = parseArgs(process.argv.slice(2));
if (args.help) { log(USAGE); return; }

const missing = ['repo', 'aem-author'].filter((k) => !args[k]);
if (missing.length) { log(USAGE); fail(`missing required argument(s): ${missing.map((m) => `--${m}`).join(', ')}`, 2); }
for (const k of ['token', 'github-token', 'password', 'pat']) {
  if (args[k]) fail('do not pass tokens as arguments; set GITHUB_TOKEN in the environment instead', 2);
}

let r = args.repo.trim().replace(/\.git$/, '').replace(/\/+$/, '')
  .replace(/^git@github\.com:/, '').replace(/^https?:\/\/(www\.)?github\.com\//, '').replace(/^github\.com\//, '');
if (!/^[A-Za-z0-9-]+\/[A-Za-z0-9._-]+$/.test(r)) fail(`--repo must be owner/name or a github.com URL, got: ${args.repo}`, 2);
const [owner, name] = r.split('/');
const ownerLc = owner.toLowerCase();
if (!/^[a-z0-9]([a-z0-9-]*[a-z0-9])?$/.test(name)) fail(`repo name '${name}' must be lowercase letters, digits and hyphens (it becomes part of the aem.page hostname)`, 2);
if (name.includes('--') || ownerLc.includes('--')) fail("owner/repo must not contain '--' (reserved separator in aem.page hostnames)", 2);

const branch = args.branch || 'main';
if (!/^[a-z0-9]([a-z0-9-]*[a-z0-9])?$/.test(branch)) fail('--branch must be lowercase letters, digits and hyphens', 2);
const hostLabel = `${branch}--${name}--${ownerLc}`;
if (hostLabel.length > 63) fail(`'${hostLabel}' is ${hostLabel.length} characters; aem.page host labels max out at 63. Use a shorter repo name.`, 2);

let aem = args['aem-author'].trim().toLowerCase().replace(/^https?:\/\//, '').split('/')[0];
if (/^publish-p\d+-e\d+\.adobeaemcloud\.com$/.test(aem)) fail(`'${aem}' is a PUBLISH host; use the AUTHOR host: ${aem.replace(/^publish-/, 'author-')}`, 2);
if (!/^author-p\d+-e\d+\.adobeaemcloud\.com$/.test(aem)) fail(`--aem-author must look like https://author-p12345-e67890.adobeaemcloud.com, got: ${args['aem-author']}`, 2);

const template = args.template || 'xwalk';
const templateRepo = TEMPLATES[template];
if (!templateRepo) fail('--template must be xwalk or xcom', 2);
const visibility = args.visibility || 'public';
if (!['public', 'private'].includes(visibility)) fail('--visibility must be public or private', 2);
const description = args.description || `${name} - AEM Edge Delivery Services site authored with Universal Editor`;

const mountUrl = `https://${aem}/bin/franklin.delivery/${owner}/${name}/${branch}`;
const fstab = `mountpoints:\n  /:\n    url: "${mountUrl}"\n    type: "markup"\n    suffix: ".html"\n`;

Object.assign(result, {
  repo: `${owner}/${name}`,
  repo_url: `https://github.com/${owner}/${name}`,
  template_repo: templateRepo,
  visibility,
  aem_author: `https://${aem}`,
  content_source_url: mountUrl,
  branch,
  preview_url: `https://${hostLabel}.aem.page`,
  live_url: `https://${hostLabel}.aem.live`,
  dry_run: !!args['dry-run'],
});

// ---------------------------------------------------------------- run
  let login = null;
  if (token) {
    const me = await gh('GET', '/user');
    if (me.status !== 200) fail(`GITHUB_TOKEN was rejected: ${ghMsg(me)}`);
    login = me.data.login;
    log(`Authenticated as ${login}`);
  } else if (!args['dry-run']) {
    fail('set GITHUB_TOKEN (or GH_TOKEN) in the environment; see --help for required scopes');
  }
  result.authenticated_as = login;

  // The template must still be a GitHub template repository.
  const tpl = await gh('GET', `/repos/${templateRepo}`);
  if (tpl.status !== 200) fail(`cannot read template ${templateRepo}: ${ghMsg(tpl)}`);
  if (!tpl.data.is_template) fail(`${templateRepo} is no longer marked as a template repository`);

  const existing = await gh('GET', `/repos/${owner}/${name}`);
  const exists = existing.status === 200;

  if (args['dry-run']) {
    result.steps.create_repo = exists ? 'would-reuse-existing' : 'would-create';
    result.steps.fstab = 'would-update';
    log(`Dry run OK. Repo ${owner}/${name} ${exists ? 'already exists (will be reused if it is an xwalk project)' : 'will be created'}.`);
    return finish(0);
  }

  // ---- Step 1: repo from template
  log(`1/2 Repository ${owner}/${name}`);
  if (exists) {
    const marker = await gh('GET', `/repos/${owner}/${name}/contents/component-definition.json?ref=${branch}`);
    if (marker.status !== 200) fail(`${owner}/${name} already exists and is not a Universal Editor (xwalk) project; refusing to modify it`);
    result.steps.create_repo = 'reused-existing';
    log('    already exists, reusing it');
  } else {
    const gen = await gh('POST', `/repos/${templateRepo}/generate`, {
      owner, name, description, private: visibility === 'private', include_all_branches: false,
    });
    if (gen.status !== 201) {
      const hint = gen.status === 404 || gen.status === 403
        ? ` (check the token can create repos under '${owner}'${login && login.toLowerCase() !== ownerLc ? ' - it is an org, so the token needs org access' : ''})`
        : '';
      fail(`could not create repo from template: ${ghMsg(gen)}${hint}`);
    }
    result.steps.create_repo = 'created';
    log(`    created from ${templateRepo}`);
  }

  // Template contents are copied asynchronously; wait for fstab.yaml.
  let file;
  for (let i = 0; i < 30; i++) {
    file = await gh('GET', `/repos/${owner}/${name}/contents/fstab.yaml?ref=${branch}`);
    if (file.status === 200) break;
    await sleep(2000);
  }

  // ---- Step 2: fstab.yaml
  log(`2/2 fstab.yaml -> ${mountUrl}`);
  let sha;
  if (file.status === 200) {
    sha = file.data.sha;
    const current = Buffer.from(file.data.content || '', 'base64').toString('utf8');
    if (current.includes(mountUrl)) {
      result.steps.fstab = 'already-up-to-date';
      log('    already points at this AEM author');
      return finish(0);
    }
  } else if (file.status !== 404) {
    fail(`could not read fstab.yaml: ${ghMsg(file)}`);
  } else if (result.steps.create_repo === 'created') {
    fail('template files did not appear within 60s; re-run the same command (it is safe to repeat)');
  }

  const put = await gh('PUT', `/repos/${owner}/${name}/contents/fstab.yaml`, {
    message: 'chore: point content source at AEM author',
    content: Buffer.from(fstab, 'utf8').toString('base64'),
    branch,
    ...(sha ? { sha } : {}),
  });
  if (put.status !== 200 && put.status !== 201) fail(`could not commit fstab.yaml: ${ghMsg(put)}`);
  result.steps.fstab = 'committed';
  result.fstab_commit = put.data.commit && put.data.commit.html_url;
  log(`    committed to ${branch}`);
  finish(0);
}

main().catch((e) => {
  if (e instanceof Done) return;
  try { fail(e && e.message ? e.message : String(e)); } catch (d) { if (!(d instanceof Done)) throw d; }
});
