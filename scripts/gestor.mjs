import { spawn } from "node:child_process";
import { readFile, writeFile } from "node:fs/promises";
import readline from "node:readline/promises";
import process from "node:process";

const rl = readline.createInterface({
  input: process.stdin,
  output: process.stdout
});

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

async function ensureLogin() {
  console.log("\nConectando con Cloudflare...");

  await run("npx", ["wrangler", "whoami"])
    .catch(async () => {
      await run("npx", ["wrangler", "login"]);
    });
}

async function putSecret(name, value) {
  if (!value) {
    throw new Error(
      `No se ha indicado un valor para ${name}.`
    );
  }

  await run(
    "npx",
    ["wrangler", "secret", "put", name],
    value
  );
}

async function deploy() {
  await run("npx", ["wrangler", "deploy"]);
}

async function installProject() {
  const projectName =
    (await rl.question(
      "Nombre técnico del proyecto (sin espacios): "
    )).trim() || "gestor-publicaciones";

  const timezone =
    (await rl.question(
      "Zona horaria [Europe/Madrid]: "
    )).trim() || "Europe/Madrid";

  const username =
    await rl.question("Cuenta publicadora principal: ");

  const password =
    await rl.question(
      "Contraseña de la cuenta principal: "
    );

  const adminKey =
    await rl.question(
      "Clave administrativa del panel: "
    );

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

  console.log("\nCreando el servicio...");
  await deploy();

  console.log("\nPreparando la base de datos...");
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

  console.log("\nGuardando credenciales...");
  await putSecret(
    "FOROACTIVO_USERNAME",
    username
  );

  await putSecret(
    "FOROACTIVO_PASSWORD",
    password
  );

  await putSecret(
    "ADMIN_API_KEY",
    adminKey
  );

  console.log("\nRegistrando la cuenta principal en el formulario...");
  await savePublisherRecord(
    username,
    "default"
  );

  let addForums = true;

  while (addForums) {
    const forumLabel =
      (await rl.question(
        "Nombre visible del foro de publicación (vacío para terminar): "
      )).trim();

    if (!forumLabel) {
      break;
    }

    const forumUrl =
      (await rl.question(
        "URL completa de ese foro: "
      )).trim();

    if (!/^https:\/\//i.test(forumUrl)) {
      throw new Error(
        "La URL del foro debe comenzar por https://"
      );
    }

    await saveForumRecord(
      forumLabel,
      forumUrl
    );

    const more =
      (await rl.question(
        "¿Añadir otro foro? (s/n): "
      )).trim().toLowerCase();

    addForums = more === "s";
  }

  console.log("\nPublicando la configuración final...");
  await deploy();

  console.log(
    "\nInstalación terminada.\n" +
    "La cuenta indicada queda como cuenta publicadora principal.\n" +
    "El formulario cargará automáticamente sus foros y cuentas.\n"
  );
}

async function changeAdminKey() {
  await ensureLogin();

  const newKey =
    await rl.question(
      "Nueva clave administrativa: "
    );

  await putSecret(
    "ADMIN_API_KEY",
    newKey
  );

  await deploy();

  console.log(
    "\nLa clave administrativa se ha actualizado.\n"
  );
}

async function changeMainPublisherAccount() {
  await ensureLogin();

  const username =
    await rl.question(
      "Nueva cuenta publicadora principal: "
    );

  const password =
    await rl.question(
      "Nueva contraseña de la cuenta principal: "
    );

  await putSecret(
    "FOROACTIVO_USERNAME",
    username
  );

  await putSecret(
    "FOROACTIVO_PASSWORD",
    password
  );

  await deploy();

  console.log(
    "\nLa cuenta publicadora principal ha sido sustituida.\n"
  );
}

async function addPublisherAccount() {
  await ensureLogin();

  const username =
    await rl.question(
      "Nombre de usuario de la nueva cuenta: "
    );

  const suggestedKey =
    normalizeAccountKey(username);

  const identifierInput =
    await rl.question(
      `Identificador para seleccionar esta cuenta [${suggestedKey}]: `
    );

  const identifier =
    normalizeAccountKey(
      identifierInput || suggestedKey
    );

  if (!identifier) {
    throw new Error(
      "No se pudo crear un identificador válido."
    );
  }

  const password =
    await rl.question(
      "Contraseña de la nueva cuenta: "
    );

  const usernameSecret =
    `FOROACTIVO_USERNAME_${identifier}`;

  const passwordSecret =
    `FOROACTIVO_PASSWORD_${identifier}`;

  await putSecret(
    usernameSecret,
    username
  );

  await putSecret(
    passwordSecret,
    password
  );

  await savePublisherRecord(
    username,
    identifier
  );

  await deploy();

  console.log(
    "\nNueva cuenta añadida correctamente.\n" +
    "Aparecerá en el desplegable con el nombre:\n\n" +
    username +
    "\n"
  );
}

async function changeMainPublisherPassword() {
  await ensureLogin();

  const password =
    await rl.question(
      "Nueva contraseña de la cuenta principal: "
    );

  await putSecret(
    "FOROACTIVO_PASSWORD",
    password
  );

  await deploy();

  console.log(
    "\nLa contraseña de la cuenta principal se ha actualizado.\n"
  );
}

async function updateAdditionalPublisherAccount() {
  await ensureLogin();

  const identifierInput =
    await rl.question(
      "Identificador de la cuenta adicional: "
    );

  const identifier =
    normalizeAccountKey(identifierInput);

  if (!identifier) {
    throw new Error(
      "El identificador no es válido."
    );
  }

  const username =
    await rl.question(
      "Nuevo nombre de usuario: "
    );

  const password =
    await rl.question(
      "Nueva contraseña: "
    );

  await putSecret(
    `FOROACTIVO_USERNAME_${identifier}`,
    username
  );

  await putSecret(
    `FOROACTIVO_PASSWORD_${identifier}`,
    password
  );

  await deploy();

  console.log(
    "\nLa cuenta adicional se ha actualizado.\n"
  );
}

async function addPublicationForum() {
  await ensureLogin();

  const label =
    (await rl.question(
      "Nombre visible del foro: "
    )).trim();

  const forumUrl =
    (await rl.question(
      "URL completa del foro: "
    )).trim();

  if (!label) {
    throw new Error(
      "El nombre visible no puede estar vacío."
    );
  }

  if (!/^https:\/\//i.test(forumUrl)) {
    throw new Error(
      "La URL debe comenzar por https://"
    );
  }

  await saveForumRecord(
    label,
    forumUrl
  );

  console.log(
    "\nForo añadido al desplegable del formulario.\n"
  );
}


async function disablePublicationForum() {
  await ensureLogin();

  const forumUrl =
    (await rl.question(
      "URL exacta del foro que quieres retirar: "
    )).trim();

  await executeRemoteSql(
    "UPDATE publication_forums SET active = 0 " +
    "WHERE forum_url = " + sqlText(forumUrl) + ";"
  );

  console.log(
    "\nEl foro se ha retirado del desplegable.\n"
  );
}


async function disableAdditionalPublisher() {
  await ensureLogin();

  const accountName =
    (await rl.question(
      "Nombre visible de la cuenta que quieres retirar: "
    )).trim();

  await executeRemoteSql(
    "UPDATE publication_accounts SET active = 0 " +
    "WHERE label = " + sqlText(accountName) + " " +
    "AND account_key <> 'default';"
  );

  console.log(
    "\nLa cuenta se ha retirado del desplegable. " +
    "Sus secretos no se muestran ni se eliminan automáticamente.\n"
  );
}


async function changeTimezone() {
  const timezone =
    (await rl.question(
      "Nueva zona horaria: "
    )).trim();

  if (!timezone) {
    throw new Error(
      "La zona horaria no puede estar vacía."
    );
  }

  const configPath =
    new URL("../wrangler.jsonc", import.meta.url);

  const raw =
    await readFile(configPath, "utf8");

  const config =
    JSON.parse(raw);

  config.vars.TIME_ZONE = timezone;

  await writeFile(
    configPath,
    JSON.stringify(config, null, 2),
    "utf8"
  );

  await ensureLogin();
  await deploy();

  console.log(
    "\nLa zona horaria se ha actualizado.\n"
  );
}

async function repairProject() {
  await ensureLogin();

  console.log("\nAplicando migraciones...");

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

  console.log("\nVolviendo a publicar el servicio...");
  await deploy();

  console.log("\nReparación terminada.\n");
}

async function menu() {
  console.log(`
========================================
  GESTOR DE PUBLICACIONES - MANTENIMIENTO
========================================

1. Instalar el proyecto
2. Cambiar la clave del panel
3. Cambiar la cuenta publicadora principal
4. Añadir una nueva cuenta publicadora
5. Cambiar la contraseña de la cuenta principal
6. Actualizar una cuenta publicadora adicional
7. Añadir un foro de publicación
8. Retirar un foro del desplegable
9. Retirar una cuenta adicional del desplegable
10. Cambiar la zona horaria
11. Reparar la instalación
12. Salir
`);

  const option =
    (await rl.question(
      "Selecciona una opción: "
    )).trim();

  switch (option) {
    case "1":
      await installProject();
      break;

    case "2":
      await changeAdminKey();
      break;

    case "3":
      await changeMainPublisherAccount();
      break;

    case "4":
      await addPublisherAccount();
      break;

    case "5":
      await changeMainPublisherPassword();
      break;

    case "6":
      await updateAdditionalPublisherAccount();
      break;

    case "7":
      await addPublicationForum();
      break;

    case "8":
      await disablePublicationForum();
      break;

    case "9":
      await disableAdditionalPublisher();
      break;

    case "10":
      await changeTimezone();
      break;

    case "11":
      await repairProject();
      break;

    case "12":
      return false;

    default:
      console.log("\\nOpción no válida.\\n");
  }

  return true;
}

async function main() {
  let keepRunning = true;

  while (keepRunning) {
    keepRunning = await menu();

    if (!keepRunning) {
      break;
    }

    const again =
      (await rl.question(
        "¿Quieres realizar otra operación? (s/n): "
      )).trim().toLowerCase();

    keepRunning = again === "s";
  }
}

main()
  .catch((error) => {
    console.error(
      "\nNo se pudo completar la operación:"
    );

    console.error(error.message);
    process.exitCode = 1;
  })
  .finally(() => rl.close());
