# Foroactivo Topic Scheduler Installer

This repository contains the source code for a Windows installer, a Cloudflare Worker backend, D1 migrations, and the HTML files used to schedule and manage automatic topic publication on Foroactivo / Forumotion-family forums.

The repository is prepared for technical review. It does not include real forum credentials, Cloudflare tokens, Wrangler sessions, generated installer runtimes, logs, D1 exports, or user-specific installation data.

## What The Project Does

The system lets a forum administrator:

- configure one or more target forums;
- configure one main publishing account and additional publishing accounts;
- create a Cloudflare Worker;
- create or reuse a Cloudflare D1 database;
- store private forum credentials as Cloudflare Worker Secrets;
- publish scheduled topics through a Worker cron;
- manage scheduled, published, cancelled, failed, paused, and processing topics from a private control panel;
- generate localized HTML files for the scheduling form, control panel, and installation instructions.

## Main Components

- `scripts/instalador-gui.ps1`
  Windows Forms installer written in PowerShell. It drives the visual installation, language selection, Cloudflare login, Worker deployment, D1 setup, secrets, maintenance actions, backups, and final file generation.

- `installer-builder/Program.cs`
  Small Windows launcher used to package the project source into a self-extracting EXE. It extracts the payload into a temporary runtime folder, starts the PowerShell GUI, waits for it to close, and then cleans the runtime folder.

- `build-installer.ps1`
  Helper script used to build the Windows EXE from the current source tree.

- `src/index.js`
  Cloudflare Worker backend. It exposes the scheduling API, panel API, public configuration endpoint, cron handler, forum login/posting flow, admin authentication, and D1 operations.

- `migrations/`
  D1 database schema migrations.

- `panel/formulario-programacion.html`
  Scheduling form template copied into a Foroactivo HTML page.

- `panel/panel-control.html`
  Private control panel template copied into a Foroactivo HTML page.

- `wrangler.jsonc`
  Base Wrangler configuration. The installer updates runtime values such as Worker name, D1 database name, D1 `database_id`, and time zone during installation.

- `SECURITY_REVIEW.md`
  Security notes for reviewers, including how secrets are handled.

- `docs/INSTALLER_INTERNAL_STRUCTURE.md`
  Detailed installer architecture and internal flow.

## Installer Architecture

The Windows EXE is not the whole application by itself. It is a launcher that embeds this project as a ZIP payload.

At runtime:

1. The EXE extracts the embedded payload into `.foroactivo_installer_runtime`.
2. It starts `scripts/instalador-gui.ps1` with PowerShell.
3. The PowerShell GUI collects project data, forum data, accounts, language, time zone, and maintenance actions.
4. The installer uses Node.js, npm/npx, Wrangler, and Cloudflare to deploy or update the Worker.
5. D1 migrations are applied.
6. Secrets are written to Cloudflare Worker Secrets.
7. Localized final files are generated in the selected installation language.
8. The runtime folder is deleted after the installer closes.

See [Installer Internal Structure](docs/INSTALLER_INTERNAL_STRUCTURE.md) for the full internal layout.

## Installation Flow

The intended end-user flow is:

1. Run the installer EXE.
2. Select the installation language.
3. Enter the project name and time zone.
4. Enter the admin panel key.
5. Enter the main publishing account.
6. Add one or more forums.
7. Add optional extra publishing accounts.
8. Start installation.
9. Authorize Cloudflare when Wrangler asks.
10. Copy the generated HTML files into Foroactivo HTML pages.

The generated final folder contains only the files needed for that selected language:

- scheduling form HTML;
- control panel HTML;
- installation instructions TXT;
- installer log TXT;
- installation metadata JSON used for future maintenance.

## Maintenance Features

The installer can also be used after a first installation to:

- update the admin panel key;
- update the main publishing account;
- add publishing accounts;
- disable/remove publishing accounts from configuration;
- add forums;
- disable/remove forums from configuration;
- refresh final HTML files;
- create backups of D1 data;
- update public configuration stored in D1.

Maintenance is intentionally handled by the installer because many administrators are not expected to work directly inside Cloudflare.

## Secrets And Credentials

Private credentials are not stored in this repository.

During installation, the following values are stored as Cloudflare Worker Secrets:

- `ADMIN_API_KEY`
- `FOROACTIVO_USERNAME`
- `FOROACTIVO_PASSWORD`
- `FOROACTIVO_USERNAME_<ACCOUNT_KEY>`
- `FOROACTIVO_PASSWORD_<ACCOUNT_KEY>`

The public form never receives passwords. It only reads public configuration through:

```text
GET /api/public-config
```

That response contains visible forum/account labels and internal identifiers only.

## Build The Installer

On Windows:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\build-installer.ps1
```

Generated files are written to:

```text
dist/
```

`dist/` is intentionally ignored by Git because EXE and ZIP files are build artifacts.

## Review Notes

Recommended review focus:

- PowerShell installer flow in `scripts/instalador-gui.ps1`;
- launcher extraction and cleanup in `installer-builder/Program.cs`;
- Worker API authorization in `src/index.js`;
- D1 migration schema in `migrations/`;
- Cloudflare Secret handling;
- generated HTML localization and runtime configuration;
- maintenance flows that update D1 and secrets without reinstalling the whole project.

## Repository Hygiene

The `.gitignore` excludes:

- generated EXE/ZIP/MSI files;
- installer runtime folders;
- `node_modules/`;
- `.wrangler/`;
- `.env*`;
- logs;
- temporary metadata folders.

This keeps the repository suitable for source review without exposing local installation artifacts.
