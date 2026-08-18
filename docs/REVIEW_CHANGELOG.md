# Review Changelog

This file summarizes the main functional areas that were added or refined before publishing this source package for review.

## Installer UI

- Windows Forms interface redesigned with a professional Win11/Office-style layout.
- Responsive layout adjusted to avoid clipped controls at 1366x768 and higher resolutions.
- Language selector added at startup and inside the installer.
- Installation progress is shown through visible steps, green check marks, error marks, and a progress bar instead of relying on a command prompt window.
- Technical details are still available inside the installer for diagnostics.

## Multilingual Support

The installer and generated files support multiple languages:

- Spanish
- English
- Portuguese
- Italian
- Russian
- French
- German
- Romanian
- Dutch

Each language generates its own localized final folder, form, panel, and instructions.

Forum platform naming is localized where appropriate, while the authorship/terms section keeps the fixed credit to Jucarese, Administrator of Foroactivo.

## Installer Packaging

- Added a C# launcher that embeds the project as a ZIP payload.
- The launcher extracts the payload to a hidden runtime folder.
- The launcher starts the PowerShell GUI and waits for it to close.
- The launcher attempts to clean runtime files after completion.
- Build artifacts are generated into `dist/` and ignored by Git.

## Cloudflare / Wrangler Flow

- The installer manages Wrangler login, Worker deployment, D1 setup, migrations, secrets, and final configuration.
- Clearer errors were added for Cloudflare session mismatch, D1 lookup failures, D1 account limits, and missing `workers.dev` subdomain onboarding.
- Maintenance mode can reuse existing installation metadata to update a Worker/D1 installation.

## D1 And Public Configuration

- D1 stores scheduled topics, status, forums, account references, public configuration, and admin settings.
- Public configuration is exposed through `/api/public-config`.
- Passwords are never returned to the public form.
- The form caches public configuration to reduce Worker/D1 load.

## Secrets

The installer writes forum credentials to Cloudflare Worker Secrets:

- `ADMIN_API_KEY`
- `FOROACTIVO_USERNAME`
- `FOROACTIVO_PASSWORD`
- additional account username/password secrets.

Maintenance mode can update or remove secrets when accounts are changed or disabled.

## Generated HTML Files

- Scheduling form and control panel templates are localized during installation.
- The scheduling form uses a Forumotion/Foroactivo-compatible editor flow.
- Smileys and image insertion were adjusted to avoid unwanted color inheritance in WYSIWYG mode.
- Date and time format controls were added to support regional preferences.

## Maintenance Features

Maintenance mode supports:

- adding forums;
- disabling/removing forums;
- adding publishing accounts;
- disabling/removing publishing accounts;
- updating the admin panel key;
- updating main publishing credentials;
- regenerating localized HTML files;
- backing up D1 data;
- updating public configuration without a full reinstall.

## Security / Review Focus

Recommended review areas:

- PowerShell command execution and argument handling.
- Wrangler command invocation.
- Cloudflare Secret writes and deletes.
- D1 migration and query safety.
- Admin panel API authentication.
- Forum login/posting implementation.
- Local runtime cleanup.
- Generated HTML security and cross-origin behavior.
