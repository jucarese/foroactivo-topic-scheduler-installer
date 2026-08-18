# Security review notes

This repository contains the source code for the Foroactivo topic scheduler installer and Cloudflare Worker.

## Secrets

No real user passwords, Cloudflare API tokens, Wrangler authentication files, D1 exports, or installed forum credentials should be committed.

The installer writes runtime credentials to Cloudflare Worker Secrets during installation:

- `ADMIN_API_KEY`
- `FOROACTIVO_USERNAME`
- `FOROACTIVO_PASSWORD`
- `FOROACTIVO_USERNAME_<ACCOUNT_KEY>`
- `FOROACTIVO_PASSWORD_<ACCOUNT_KEY>`

Those names may appear in the source code because they are the expected Secret names. The values are supplied by the installer user at runtime.

## Generated files excluded from Git

The `.gitignore` excludes:

- `node_modules/`
- `.wrangler/`
- `.env*`
- generated ZIP/EXE/MSI files
- installer runtime folders
- logs and local output files

## Cloudflare configuration

`wrangler.jsonc` contains a generic Worker/D1 configuration. The installer updates runtime values such as project name and D1 `database_id` during installation.

## Recommended review focus

- Cloudflare Worker API authorization.
- D1 migration schema.
- Secret handling during install/update/maintenance.
- Forum login/posting flow.
- Installer language switching and generated localized HTML files.
