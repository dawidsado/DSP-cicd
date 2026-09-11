# SAP Datasphere CI/CD - DEV to PROD transport

Manage SAP Datasphere object transport as code, using the Datasphere CLI, Git and
GitHub Actions. Object definitions live as files in this repository, so every change
gets a diff, a review, history and rollback for free.

## What it does

Objects (local tables and a data flow with a Python transformation) are collected
from a source space (DEV), versioned in Git, and deployed to a target space (PROD)
by a pipeline. No manual clicking in the Datasphere UI.

## The transport building blocks

| Step            | CLI command                                                        |
|-----------------|--------------------------------------------------------------------|
| List objects    | `datasphere objects <type> list --space DEV`                       |
| Read definition | `datasphere objects <type> read --space DEV --technical-name X`    |
| Write object    | `datasphere objects <type> create|update --space PROD ...`         |

`create` / `update` deploy the object after saving (unless `--no-deploy` is used).

## Daily loop

1. Model something in DEV (in the Datasphere UI).
2. Collect the objects into files: `read` (overwrites the JSON files under `objects/`).
3. `git diff` shows exactly what changed - line by line.
4. Open a Pull Request. The pipeline posts a **plan** as a comment (what will be
   created / updated in PROD) without touching the tenant.
5. Merge to main. The pipeline deploys to PROD and writes a summary in the Actions tab.

## Deployment order matters

Objects have dependencies: a data flow depends on its source and target tables.
`deploy.sh` deploys types in dependency order - tables first, then the flow - so
associations resolve correctly.

## Authentication (headless)

The pipeline authenticates with a **Technical User** OAuth client
(`client_credentials` grant), which works without a browser. Two things every CLI
call needs in CI:

- `--host` - so the CLI knows which tenant (and command cache) to use.
- `--secrets-file` - the credentials, injected in CI from the `DSP_SECRETS` repo secret.

The CLI also needs `datasphere config cache init --host ...` once per run to download
the list of tenant-specific commands (like `objects`).

## Requirements

- Node.js 20-24, `@sap/datasphere-cli`, `jq`.
- A Technical User OAuth client with a scoped role (e.g. DW Modeler) granting access
  to both the DEV and PROD spaces.

## Repository secrets / variables (GitHub)

- Secret `DSP_SECRETS` - the full contents of a working `config/secrets.json`.
- Variable `SPACE_TARGET` - the target space id (e.g. `PROD`).

## Notes

- The Python transformation inside the data flow travels with the flow definition.

## Run it yourself

Everything runs against **your own** SAP Datasphere tenant with **your own**
credentials. Nothing here contains real secrets — you generate your own.

### 1. Create a Technical User OAuth client

In SAP Datasphere: **System → Administration → App Integration → Add a New OAuth Client**.

- **Purpose:** `Technical User` (uses the `client_credentials` grant, so it works
  headless — no browser login needed in CI).
- **User ID:** any unique name, e.g. `github_technical_user`.
- **Roles:** assign a scoped role (e.g. **DW Modeler**) that grants access to your
  source and target spaces, with privileges for Data Builder and Space Files.

After saving, copy the **Client ID** and **Client Secret** (the secret is shown once).

> Note: a scoped role only applies to the spaces attached to it. Make sure your role
> covers **both** the source (DEV) and target (PROD) spaces — otherwise the CLI
> returns `403 Forbidden`.

### 2. Log in and generate the secrets file

Install the CLI and `jq`:

```bash
npm install -g @sap/datasphere-cli
```

Log in with the technical user (single quotes matter — the client id often contains `!`):

```bash
datasphere login \
  --authorization-flow client_credentials \
  --client-id 'YOUR_CLIENT_ID' \
  --client-secret 'YOUR_CLIENT_SECRET' \
  --token-url 'YOUR_TOKEN_URL' \
  --host 'https://your-tenant.region.hcs.cloud.sap'
```

Export the session to a secrets file:

```bash
mkdir -p config
datasphere config secrets show > config/secrets.json
```

The output is an array — reduce it to a single object and make sure it contains a
`host` field. See `config/secrets.example.json` for the expected shape.

> `config/secrets.json` is git-ignored and must **never** be committed — it holds
> your tenant tokens.

### 3. Test access

```bash
datasphere objects local-tables list \
  --space YOUR_SPACE \
  --host 'https://your-tenant.region.hcs.cloud.sap' \
  --secrets-file config/secrets.json
```

An empty list `[]` means access works. A `403` means the scoped role doesn't cover
that space (see step 1).

### 4. Configure GitHub

In your repo: **Settings → Secrets and variables → Actions**.

- **Secret** `DSP_SECRETS` — paste the full contents of your working
  `config/secrets.json`.
- **Variable** `SPACE_TARGET` — your target space id (e.g. `PROD`).

Update `DSP_HOST` in `scripts/deploy.sh` and `.github/workflows/deploy.yml` to point
to your own tenant.

### 5. Collect and deploy

Collect objects from your source space into `objects/`, commit, and push. On push to
`main`, the pipeline deploys them to the target space. On a pull request, it posts a
plan (dry-run) as a comment first.

### Notes on the CLI in CI

Two things every CLI call needs in a headless environment:

- `--host` — so the CLI knows which tenant (and command cache) to use. Without it you
  may get `unknown command 'objects'`.
- `--secrets-file` — the credentials for headless authentication.

The workflow also runs `datasphere config cache init --host ...` once per run to
download the tenant-specific command list. Node.js 20–24 is required.