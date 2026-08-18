# Gestor de publicaciones para Foroactivo — v1.0

Esta versión está preparada para pruebas.

## Instalación rápida

Requisitos:
- Una cuenta gratuita de Cloudflare.
- Node.js 20 o superior.

Pasos:

1. Descomprime esta carpeta.
2. Abre una terminal dentro de la carpeta.
3. Ejecuta:

   npm install
   npm run install:v1

4. El instalador pedirá:
   - nombre técnico del proyecto;
   - zona horaria;
   - cuenta publicadora;
   - contraseña;
   - clave administrativa.

5. Cloudflare abrirá una sola página para autorizar la instalación.
6. El proceso crea automáticamente:
   - el Worker;
   - la base D1;
   - la tabla;
   - el cron de cada minuto;
   - las variables;
   - los secretos.

7. Copia `panel/panel-control.html` en una página HTML de Foroactivo.
8. Al abrirla por primera vez, indica:
   - el nombre visible que quieras dar al proyecto;
   - la dirección `https://...workers.dev` creada durante la instalación.

## Importante

- El nombre visible del panel puede ser cualquiera.
- El nombre técnico del Worker también puede cambiarse durante la instalación.
- La clave admite Ñ, tildes y símbolos.
- Eliminar registros del panel no elimina temas reales del foro.
- Las credenciales privadas se guardan como secretos de Cloudflare.

## Archivos principales

- `src/index.js`: motor del sistema.
- `panel/panel-control.html`: página de control.
- `migrations/0001_initial.sql`: estructura de la base de datos.
- `wrangler.jsonc`: configuración automática.
- `scripts/instalar.mjs`: instalador guiado.


## Centro de mantenimiento

Ejecuta:

```text
npm run gestor
```

Opciones disponibles:

- instalar el proyecto;
- cambiar la clave del panel;
- cambiar la cuenta publicadora;
- cambiar únicamente la contraseña de la cuenta publicadora;
- cambiar la zona horaria;
- reparar la instalación.

Las nuevas credenciales se guardan como secretos de Cloudflare y sustituyen a las anteriores.


## Varias cuentas publicadoras

La cuenta creada durante la instalación es la cuenta principal.

Desde:

```text
npm run gestor
```

puedes elegir:

- **Cambiar la cuenta publicadora principal**: sustituye la actual.
- **Añadir una nueva cuenta publicadora**: conserva la principal y añade otra.
- **Actualizar una cuenta adicional**: modifica las credenciales de una cuenta añadida.

Cada cuenta adicional recibe un identificador, por ejemplo:

```text
NOTICIAS
EVENTOS
STAFF_2
```

Ese identificador es el que debe indicarse en el campo **Cuenta publicadora** de la programación.

La cuenta principal puede seguir seleccionándose escribiendo su nombre de usuario o `default`.


## Configuración automática del formulario

Los foros y las cuentas publicadoras se guardan en D1 mediante el instalador.

El formulario consulta:

```text
GET /api/public-config
```

La respuesta solo contiene:
- nombres visibles de cuentas;
- identificadores internos;
- nombres y URLs de foros.

Nunca contiene contraseñas.

Para reducir consumo:
- el Worker permite caché durante 5 minutos;
- el formulario guarda la lista en el navegador durante 24 horas;
- solo vuelve a consultar al caducar la caché o al pulsar **Refresh lists**.


## Instalador visual

### Windows

Haz doble clic en:

```text
ABRIR_INSTALADOR.bat
```

La primera vez instalará automáticamente las dependencias y abrirá el asistente en el navegador.

### macOS y Linux

Ejecuta:

```text
sh abrir-instalador.sh
```

El asistente permite:
- introducir el nombre del proyecto;
- elegir la zona horaria;
- crear la clave del panel;
- añadir la cuenta principal;
- añadir varios foros;
- añadir varias cuentas publicadoras;
- revisar toda la configuración antes de instalar.

No cierres la ventana de comandos mientras el asistente esté funcionando.


## Instalación gráfica en Windows

Haz doble clic en:

```text
INSTALAR_SIN_CONSOLA.bat
```

Se abrirá una ventana gráfica, sin consola visible.

Desde ella puedes configurar:
- nombre del proyecto;
- zona horaria;
- clave del panel;
- cuenta principal;
- varios foros;
- varias cuentas adicionales;
- progreso de la instalación.

Cloudflare puede abrir el navegador una sola vez para autorizar la cuenta.

Requisito: Node.js debe estar instalado.


## Cambios del instalador v1.4

- La clave administrativa del panel se muestra mientras se escribe.
- Se puede ocultar marcando **Ocultar clave**.
- La advertencia de migración de D1 se confirma automáticamente.
- El usuario ya no tiene que responder `y` durante la instalación.
