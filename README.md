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

- `config/secrets.json` is never committed (see `.gitignore`) - it holds tenant tokens.
- The Python transformation inside the data flow travels with the flow definition.