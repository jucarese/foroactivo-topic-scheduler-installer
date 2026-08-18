# Installer Internal Structure

This document explains how the Windows installer is structured internally, how the EXE is built, what each folder does, and how the installer connects the local GUI, Cloudflare Worker, D1 database, secrets, and generated HTML files.

## High-Level Architecture

```text
Windows EXE
  |
  |-- embeds project source as InstallerPayload.zip
  |
  |-- extracts payload to .foroactivo_installer_runtime/
  |
  |-- launches PowerShell Windows Forms GUI
  |
  |-- GUI deploys / updates Cloudflare Worker
  |
  |-- GUI creates / updates D1 database
  |
  |-- GUI writes Worker Secrets
  |
  |-- GUI generates localized HTML files
  |
  |-- launcher removes runtime folder when the GUI closes
```

The installer is designed for non-technical forum administrators. Most Cloudflare and Wrangler operations are hidden behind a Windows Forms interface.

## Repository Layout

```text
.
|-- assets/
|-- docs/
|-- installer-builder/
|-- migrations/
|-- panel/
|-- scripts/
|-- src/
|-- build-installer.ps1
|-- package.json
|-- wrangler.jsonc
|-- README.md
|-- SECURITY_REVIEW.md
```

## `assets/`

Contains branding files used by the installer:

- installer icon;
- header/logo image;
- reference image assets.

The same icon is used by the Windows Forms installer and the generated EXE.

## `installer-builder/`

Contains the C# launcher source:

```text
installer-builder/Program.cs
```

The launcher is intentionally small. Its responsibilities are:

1. Locate its own EXE directory.
2. Clean any previous `.foroactivo_installer_runtime` folder.
3. Extract the embedded `InstallerPayload.zip`.
4. Locate `scripts/instalador-gui.ps1`.
5. Start PowerShell in STA mode.
6. Pass runtime environment variables to the GUI.
7. Wait for the GUI to finish.
8. Kill/clean installer runtime leftovers when possible.

Important environment variables passed to the PowerShell GUI:

```text
FOROACTIVO_INSTALLER_OUTPUT_BASE_DIR
FOROACTIVO_INSTALLER_RUNTIME_DIR
TMP
TEMP
npm_config_cache
```

These variables help keep runtime files inside the installer folder instead of scattering temporary files around the user profile.

## `build-installer.ps1`

Builds the final Windows EXE.

It does three main things:

1. Creates a ZIP payload from the project source.
2. Compiles `installer-builder/Program.cs`.
3. Embeds the ZIP payload as a C# resource named:

```text
InstallerPayload.zip
```

Generated build artifacts are written to:

```text
dist/
```

The `dist/` folder is ignored by Git.

## `scripts/instalador-gui.ps1`

This is the main installer GUI.

It is a PowerShell Windows Forms application. It contains:

- language selection;
- Win11/Office-style visual layout;
- project settings form;
- forum configuration grid;
- publishing accounts grid;
- progress list with check marks;
- technical log panel;
- Cloudflare login checks;
- Wrangler command execution;
- D1 creation/reuse logic;
- D1 migration execution;
- Worker deployment;
- Worker Secret creation/update/removal;
- public configuration generation;
- maintenance flows;
- localized final file generation.

The installer supports multiple languages and chooses the output folder and final filenames according to the selected language.

## Installer Tabs

The GUI is organized into tabs:

```text
Project
Forums
Additional accounts
Progress
Maintenance / update actions
```

Exact labels are localized per language.

## Main Install Flow

The normal installation sequence is:

1. Check Node.js and required tools.
2. Install project dependencies.
3. Prepare Cloudflare configuration.
4. Check Cloudflare session.
5. Publish the Worker.
6. Apply D1 migrations.
7. Save credentials and panel key as Worker Secrets.
8. Register forums and additional accounts in D1.
9. Publish final Worker configuration.
10. Prepare final forum files.

Each step is shown in the GUI progress area. Completed steps receive a green check mark; failed steps are marked with an error icon.

## Cloudflare And Wrangler

The installer uses Wrangler through Node/npm/npx.

Typical operations:

```text
npx wrangler login
npx wrangler deploy
npx wrangler d1 create
npx wrangler d1 execute
npx wrangler secret put
npx wrangler secret delete
```

The installer avoids asking the user to manually run those commands.

## D1 Database

The D1 database stores:

- scheduled topics;
- topic status;
- target forums;
- publishing account references;
- public form configuration;
- admin panel settings;
- maintenance metadata.

Actual forum passwords are not stored in D1.

## Worker Secrets

Sensitive credentials are stored as Cloudflare Worker Secrets.

Main account:

```text
FOROACTIVO_USERNAME
FOROACTIVO_PASSWORD
```

Admin panel key:

```text
ADMIN_API_KEY
```

Additional accounts:

```text
FOROACTIVO_USERNAME_<ACCOUNT_KEY>
FOROACTIVO_PASSWORD_<ACCOUNT_KEY>
```

The `<ACCOUNT_KEY>` is generated from the account label/username and normalized for Cloudflare secret naming rules.

## Worker Backend

The Worker lives in:

```text
src/index.js
```

Main responsibilities:

- receive scheduled topics from the form;
- authenticate admin panel requests;
- expose public configuration to the form;
- store scheduled records in D1;
- run cron checks every minute;
- log in to the target forum account;
- publish topics when their scheduled time arrives;
- update topic status;
- support panel maintenance actions.

## HTML Templates

Templates are stored in:

```text
panel/formulario-programacion.html
panel/panel-control.html
```

The installer converts these templates into localized final files during installation.

Examples of generated final files:

```text
SCHEDULING_FORM.html
CONTROL_PANEL.html
INSTALLATION_INSTRUCTIONS.txt
```

The exact names depend on the selected language.

## Generated Installation Folder

After installation, the user receives a language-specific folder containing only the files needed for that installation.

Typical contents:

```text
CONTROL_PANEL.html
SCHEDULING_FORM.html
INSTALLATION_INSTRUCTIONS.txt
INSTALLER_LOG.txt
.foroactivo-installation.json
backups/
```

The metadata JSON is used by maintenance actions to know which Worker, D1 database, and language belong to that installation.

## Maintenance Mode

Maintenance mode allows the installer to update an existing installation without reinstalling everything.

Typical maintenance operations:

- add forums;
- disable/remove forums;
- add publishing accounts;
- disable/remove publishing accounts;
- update the admin panel key;
- update main account credentials;
- regenerate HTML files;
- backup D1 data;
- update public configuration.

The installer reads the installation metadata and verifies that the linked Worker/D1 respond in the active Cloudflare account before changing data.

## Runtime Cleanup

The EXE launcher tries to remove:

- `.foroactivo_installer_runtime`;
- temporary payload ZIP;
- temporary npm cache;
- transient metadata folders generated during installation.

This is intended to leave only the final user-facing installation folder.

## What Should Not Be Committed

The repository must not contain:

- generated EXE files;
- generated ZIP payloads;
- local installer logs;
- `.wrangler/`;
- `.env` files;
- Cloudflare API tokens;
- forum usernames/passwords from real installations;
- D1 backup files with private data;
- installation metadata from real deployments.

The `.gitignore` is configured accordingly.

## Review Checklist

For a technical review, inspect:

- `installer-builder/Program.cs` for extraction, launch, and cleanup behavior;
- `scripts/instalador-gui.ps1` for GUI flow, Wrangler command execution, localization, maintenance actions, and secret handling;
- `src/index.js` for Worker API, admin authentication, public config, cron, forum login, and posting logic;
- `migrations/` for D1 schema;
- `panel/` for generated HTML behavior;
- `SECURITY_REVIEW.md` for credential handling notes.
