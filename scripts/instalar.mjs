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
      child.stdin.write(inputValue + "\n");
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

async function main() {
  console.log("\nINSTALACIÓN DEL GESTOR DE PUBLICACIONES\n");

  const projectName =
    (await rl.question(
      "Nombre técnico del proyecto (sin espacios): "
    )).trim() || "gestor-publicaciones";

  const timezone =
    (await rl.question(
      "Zona horaria [Europe/Madrid]: "
    )).trim() || "Europe/Madrid";

  const username =
    await rl.question("Cuenta publicadora: ");

  const password =
    await rl.question("Contraseña de la cuenta publicadora: ");

  const adminKey =
    await rl.question("Clave administrativa del panel: ");

  const configPath = new URL("../wrangler.jsonc", import.meta.url);
  const raw = await readFile(configPath, "utf8");
  const config = JSON.parse(raw);

  config.name = projectName;
  config.vars.TIME_ZONE = timezone;
  config.d1_databases[0].database_name =
    `${projectName}-db`;

  await writeFile(
    configPath,
    JSON.stringify(config, null, 2),
    "utf8"
  );

  console.log("\n1/5 Conectando con Cloudflare...");
  await run("npx", ["wrangler", "login"]);

  console.log("\n2/5 Creando y publicando el servicio...");
  await run("npx", ["wrangler", "deploy"]);

  console.log("\n3/5 Preparando la base de datos...");
  await run(
    "npx",
    ["wrangler", "d1", "migrations", "apply", "DB", "--remote"]
  );

  console.log("\n4/5 Guardando credenciales privadas...");
  await run(
    "npx",
    ["wrangler", "secret", "put", "FOROACTIVO_USERNAME"],
    username
  );
  await run(
    "npx",
    ["wrangler", "secret", "put", "FOROACTIVO_PASSWORD"],
    password
  );
  await run(
    "npx",
    ["wrangler", "secret", "put", "SCHEDULE_ADMIN_KEY"],
    adminKey
  );

  console.log("\n5/5 Publicando la configuración final...");
  await run("npx", ["wrangler", "deploy"]);

  console.log(
    "\nINSTALACIÓN TERMINADA.\n" +
    "Copia panel/panel-control.html en una página HTML del foro.\n" +
    "La primera vez que la abras te pedirá el nombre visible " +
    "del proyecto y la dirección workers.dev creada.\n"
  );
}

main()
  .catch((error) => {
    console.error("\nNo se pudo completar la instalación:");
    console.error(error.message);
    process.exitCode = 1;
  })
  .finally(() => rl.close());
