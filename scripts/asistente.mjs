import http from "node:http";
import { spawn } from "node:child_process";
import { readFile, writeFile } from "node:fs/promises";
import { URL } from "node:url";
import process from "node:process";

const HOST = "127.0.0.1";
const PORT = 4173;

function run(command, args, inputValue = null) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, {
      shell: process.platform === "win32",
      stdio: [
        inputValue === null ? "inherit" : "pipe",
        "inherit",
        "inherit"
      ]
    });

    if (inputValue !== null) {
      child.stdin.write(String(inputValue) + "\n");
      child.stdin.end();
    }

    child.on("exit", (code) => {
      if (code === 0) {
        resolve();
      } else {
        reject(
          new Error(`${command} terminó con código ${code}`)
        );
      }
    });
  });
}

function normalizeAccountKey(value) {
  return String(value || "")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toUpperCase()
    .replace(/[^A-Z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "");
}

function sqlText(value) {
  return "'" +
    String(value == null ? "" : value)
      .replace(/'/g, "''") +
    "'";
}

async function ensureLogin() {
  try {
    await run("npx", ["wrangler", "whoami"]);
  } catch {
    await run("npx", ["wrangler", "login"]);
  }
}

async function putSecret(name, value) {
  await run(
    "npx",
    ["wrangler", "secret", "put", name],
    value
  );
}

async function executeRemoteSql(command) {
  await run(
    "npx",
    [
      "wrangler",
      "d1",
      "execute",
      "DB",
      "--remote",
      "--command",
      command
    ]
  );
}

async function savePublisherRecord(label, accountKey) {
  await executeRemoteSql(
    "INSERT INTO publication_accounts " +
    "(label, account_key, active) VALUES (" +
    sqlText(label) + ", " +
    sqlText(accountKey) + ", 1) " +
    "ON CONFLICT(account_key) DO UPDATE SET " +
    "label = excluded.label, active = 1;"
  );
}

async function saveForumRecord(label, forumUrl) {
  await executeRemoteSql(
    "INSERT INTO publication_forums " +
    "(label, forum_url, active) VALUES (" +
    sqlText(label) + ", " +
    sqlText(forumUrl) + ", 1) " +
    "ON CONFLICT(forum_url) DO UPDATE SET " +
    "label = excluded.label, active = 1;"
  );
}

function readBody(request) {
  return new Promise((resolve, reject) => {
    let data = "";

    request.on("data", (chunk) => {
      data += chunk;

      if (data.length > 2_000_000) {
        reject(new Error("Solicitud demasiado grande."));
        request.destroy();
      }
    });

    request.on("end", () => resolve(data));
    request.on("error", reject);
  });
}

function json(response, status, payload) {
  response.writeHead(status, {
    "Content-Type": "application/json; charset=UTF-8",
    "Cache-Control": "no-store"
  });

  response.end(JSON.stringify(payload));
}

function html(response, status, content) {
  response.writeHead(status, {
    "Content-Type": "text/html; charset=UTF-8",
    "Cache-Control": "no-store"
  });

  response.end(content);
}

function openBrowser(url) {
  const platform = process.platform;

  if (platform === "win32") {
    spawn("cmd", ["/c", "start", "", url], {
      detached: true,
      stdio: "ignore"
    }).unref();
    return;
  }

  if (platform === "darwin") {
    spawn("open", [url], {
      detached: true,
      stdio: "ignore"
    }).unref();
    return;
  }

  spawn("xdg-open", [url], {
    detached: true,
    stdio: "ignore"
  }).unref();
}

async function installProject(data) {
  const projectName = String(
    data.projectName || "gestor-publicaciones"
  ).trim();

  const timezone = String(
    data.timezone || "Europe/Madrid"
  ).trim();

  const adminKey = String(
    data.adminKey || ""
  );

  const mainUsername = String(
    data.mainUsername || ""
  ).trim();

  const mainPassword = String(
    data.mainPassword || ""
  );

  const forums = Array.isArray(data.forums)
    ? data.forums
    : [];

  const accounts = Array.isArray(data.accounts)
    ? data.accounts
    : [];

  if (
    !projectName ||
    !adminKey ||
    !mainUsername ||
    !mainPassword
  ) {
    throw new Error(
      "Faltan datos obligatorios de instalación."
    );
  }

  const configPath =
    new URL("../wrangler.jsonc", import.meta.url);

  const raw =
    await readFile(configPath, "utf8");

  const config =
    JSON.parse(raw);

  config.name = projectName;
  config.vars.TIME_ZONE = timezone;
  config.d1_databases[0].database_name =
    `${projectName}-db`;

  await writeFile(
    configPath,
    JSON.stringify(config, null, 2),
    "utf8"
  );

  await ensureLogin();

  await run("npx", ["wrangler", "deploy"]);

  await run(
    "npx",
    [
      "wrangler",
      "d1",
      "migrations",
      "apply",
      "DB",
      "--remote"
    ]
  );

  await putSecret(
    "FOROACTIVO_USERNAME",
    mainUsername
  );

  await putSecret(
    "FOROACTIVO_PASSWORD",
    mainPassword
  );

  await putSecret(
    "ADMIN_API_KEY",
    adminKey
  );

  await savePublisherRecord(
    mainUsername,
    "default"
  );

  for (const forum of forums) {
    const label = String(
      forum.label || ""
    ).trim();

    const url = String(
      forum.url || ""
    ).trim();

    if (label && /^https:\/\//i.test(url)) {
      await saveForumRecord(label, url);
    }
  }

  for (const account of accounts) {
    const username = String(
      account.username || ""
    ).trim();

    const password = String(
      account.password || ""
    );

    const label = String(
      account.label || username
    ).trim();

    if (!username || !password) {
      continue;
    }

    const accountKey =
      normalizeAccountKey(username);

    await putSecret(
      `FOROACTIVO_USERNAME_${accountKey}`,
      username
    );

    await putSecret(
      `FOROACTIVO_PASSWORD_${accountKey}`,
      password
    );

    await savePublisherRecord(
      label || username,
      accountKey
    );
  }

  await run("npx", ["wrangler", "deploy"]);

  return {
    ok: true,
    projectName
  };
}

const page = `<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Instalador del gestor de publicaciones</title>

  <style>
    :root {
      --bg: #f4f6f8;
      --card: #fff;
      --text: #1f2937;
      --muted: #6b7280;
      --border: #d1d5db;
      --primary: #2563eb;
      --primary-hover: #1d4ed8;
      --danger: #dc2626;
      --shadow: 0 12px 35px rgba(0,0,0,.10);
    }

    * { box-sizing: border-box; }

    body {
      margin: 0;
      background: var(--bg);
      color: var(--text);
      font-family: Arial, Helvetica, sans-serif;
    }

    .app {
      width: min(980px, calc(100% - 24px));
      margin: 28px auto;
    }

    .header {
      margin-bottom: 18px;
    }

    h1 {
      margin: 0 0 6px;
      font-size: 30px;
    }

    .muted {
      color: var(--muted);
    }

    .card {
      background: var(--card);
      border: 1px solid var(--border);
      border-radius: 14px;
      box-shadow: var(--shadow);
      padding: 20px;
      margin-bottom: 16px;
    }

    .grid {
      display: grid;
      grid-template-columns: 1fr 1fr;
      gap: 14px;
    }

    .full {
      grid-column: 1 / -1;
    }

    label {
      display: block;
      font-weight: 700;
      margin-bottom: 6px;
      font-size: 13px;
    }

    input {
      width: 100%;
      padding: 10px 12px;
      border: 1px solid var(--border);
      border-radius: 8px;
      font: inherit;
    }

    .row-item {
      border: 1px solid var(--border);
      border-radius: 10px;
      padding: 14px;
      margin-top: 10px;
      background: #f9fafb;
    }

    .actions {
      display: flex;
      gap: 10px;
      flex-wrap: wrap;
      margin-top: 12px;
    }

    button {
      border: 0;
      border-radius: 8px;
      padding: 10px 14px;
      font: inherit;
      font-weight: 700;
      cursor: pointer;
    }

    .primary {
      background: var(--primary);
      color: #fff;
    }

    .primary:hover {
      background: var(--primary-hover);
    }

    .light {
      background: #fff;
      border: 1px solid var(--border);
    }

    .danger {
      background: var(--danger);
      color: #fff;
    }

    .status {
      display: none;
      margin-top: 16px;
      padding: 12px 14px;
      border-radius: 8px;
      white-space: pre-wrap;
    }

    .status.show {
      display: block;
    }

    .status.info {
      background: #dbeafe;
      color: #1e40af;
      border: 1px solid #93c5fd;
    }

    .status.ok {
      background: #dcfce7;
      color: #166534;
      border: 1px solid #86efac;
    }

    .status.error {
      background: #fee2e2;
      color: #991b1b;
      border: 1px solid #fca5a5;
    }

    @media (max-width: 720px) {
      .grid {
        grid-template-columns: 1fr;
      }

      .full {
        grid-column: auto;
      }
    }
  </style>
</head>

<body>
  <main class="app">
    <header class="header">
      <h1>Instalador del gestor de publicaciones</h1>
      <div class="muted">
        Completa los datos y pulsa Instalar. No tendrás que crear manualmente el Worker, D1, las tablas ni los secretos.
      </div>
    </header>

    <section class="card">
      <h2>Proyecto</h2>

      <div class="grid">
        <div>
          <label for="projectName">Nombre técnico</label>
          <input id="projectName" value="gestor-publicaciones">
        </div>

        <div>
          <label for="timezone">Zona horaria</label>
          <input id="timezone" value="Europe/Madrid">
        </div>

        <div class="full">
          <label for="adminKey">Clave del panel</label>
          <input id="adminKey" type="password" autocomplete="new-password">
        </div>
      </div>
    </section>

    <section class="card">
      <h2>Cuenta publicadora principal</h2>

      <div class="grid">
        <div>
          <label for="mainUsername">Nombre de usuario</label>
          <input id="mainUsername">
        </div>

        <div>
          <label for="mainPassword">Contraseña</label>
          <input id="mainPassword" type="password" autocomplete="new-password">
        </div>
      </div>
    </section>

    <section class="card">
      <h2>Foros de publicación</h2>
      <div id="forums"></div>

      <div class="actions">
        <button id="addForum" class="light" type="button">
          Añadir foro
        </button>
      </div>
    </section>

    <section class="card">
      <h2>Cuentas publicadoras adicionales</h2>
      <div class="muted">
        Son opcionales. La cuenta principal ya se añade automáticamente.
      </div>

      <div id="accounts"></div>

      <div class="actions">
        <button id="addAccount" class="light" type="button">
          Añadir cuenta
        </button>
      </div>
    </section>

    <section class="card">
      <div class="actions">
        <button id="installButton" class="primary" type="button">
          Instalar
        </button>
      </div>

      <div id="status" class="status"></div>
    </section>
  </main>

  <script>
    const byId = (id) =>
      document.getElementById(id);

    function showStatus(type, text) {
      const box = byId("status");
      box.className = "status show " + type;
      box.textContent = text;
    }

    function addForumRow(data = {}) {
      const wrapper = document.createElement("div");
      wrapper.className = "row-item";

      wrapper.innerHTML = \`
        <div class="grid">
          <div>
            <label>Nombre visible</label>
            <input class="forum-label" value="\${data.label || ""}">
          </div>

          <div>
            <label>URL completa del foro</label>
            <input class="forum-url" value="\${data.url || ""}">
          </div>
        </div>

        <div class="actions">
          <button type="button" class="danger remove-row">
            Eliminar
          </button>
        </div>
      \`;

      wrapper.querySelector(".remove-row")
        .addEventListener("click", () => {
          wrapper.remove();
        });

      byId("forums").appendChild(wrapper);
    }

    function addAccountRow(data = {}) {
      const wrapper = document.createElement("div");
      wrapper.className = "row-item";

      wrapper.innerHTML = \`
        <div class="grid">
          <div>
            <label>Nombre visible</label>
            <input class="account-label" value="\${data.label || ""}">
          </div>

          <div>
            <label>Usuario de Foroactivo</label>
            <input class="account-username" value="\${data.username || ""}">
          </div>

          <div class="full">
            <label>Contraseña</label>
            <input class="account-password" type="password" autocomplete="new-password">
          </div>
        </div>

        <div class="actions">
          <button type="button" class="danger remove-row">
            Eliminar
          </button>
        </div>
      \`;

      wrapper.querySelector(".remove-row")
        .addEventListener("click", () => {
          wrapper.remove();
        });

      byId("accounts").appendChild(wrapper);
    }

    function collectForums() {
      return Array.from(
        document.querySelectorAll("#forums .row-item")
      ).map((row) => ({
        label: row.querySelector(".forum-label").value.trim(),
        url: row.querySelector(".forum-url").value.trim()
      })).filter((item) => item.label && item.url);
    }

    function collectAccounts() {
      return Array.from(
        document.querySelectorAll("#accounts .row-item")
      ).map((row) => ({
        label: row.querySelector(".account-label").value.trim(),
        username: row.querySelector(".account-username").value.trim(),
        password: row.querySelector(".account-password").value
      })).filter((item) => item.username && item.password);
    }

    byId("addForum").addEventListener(
      "click",
      () => addForumRow()
    );

    byId("addAccount").addEventListener(
      "click",
      () => addAccountRow()
    );

    byId("installButton").addEventListener(
      "click",
      async () => {
        const button = byId("installButton");

        const payload = {
          projectName: byId("projectName").value.trim(),
          timezone: byId("timezone").value.trim(),
          adminKey: byId("adminKey").value,
          mainUsername: byId("mainUsername").value.trim(),
          mainPassword: byId("mainPassword").value,
          forums: collectForums(),
          accounts: collectAccounts()
        };

        if (
          !payload.projectName ||
          !payload.adminKey ||
          !payload.mainUsername ||
          !payload.mainPassword
        ) {
          showStatus(
            "error",
            "Completa todos los campos obligatorios."
          );
          return;
        }

        button.disabled = true;
        button.textContent = "Instalando...";

        showStatus(
          "info",
          "La instalación puede tardar varios minutos. Si Cloudflare necesita autorización, se abrirá una pestaña del navegador."
        );

        try {
          const response = await fetch("/install", {
            method: "POST",
            headers: {
              "Content-Type": "application/json"
            },
            body: JSON.stringify(payload)
          });

          const data = await response.json();

          if (!response.ok || data.ok === false) {
            throw new Error(
              data.error || "No se pudo completar la instalación."
            );
          }

          showStatus(
            "ok",
            "Instalación terminada. Ya puedes cerrar esta ventana y copiar los archivos HTML de la carpeta panel a Foroactivo."
          );

        } catch (error) {
          showStatus(
            "error",
            error.message
          );

        } finally {
          button.disabled = false;
          button.textContent = "Instalar";
        }
      }
    );

    addForumRow();
  </script>
</body>
</html>`;

const server = http.createServer(async (request, response) => {
  const url = new URL(
    request.url,
    `http://${HOST}:${PORT}`
  );

  if (
    request.method === "GET" &&
    url.pathname === "/"
  ) {
    html(response, 200, page);
    return;
  }

  if (
    request.method === "POST" &&
    url.pathname === "/install"
  ) {
    try {
      const body = await readBody(request);
      const data = JSON.parse(body || "{}");

      const result = await installProject(data);
      json(response, 200, result);

    } catch (error) {
      json(response, 500, {
        ok: false,
        error:
          error && error.message
            ? error.message
            : String(error)
      });
    }

    return;
  }

  json(response, 404, {
    ok: false,
    error: "Ruta no encontrada."
  });
});

server.listen(PORT, HOST, () => {
  const url = `http://${HOST}:${PORT}`;

  console.log(
    "\nAsistente iniciado:\n" +
    url +
    "\n\nNo cierres esta ventana hasta terminar.\n"
  );

  openBrowser(url);
});
