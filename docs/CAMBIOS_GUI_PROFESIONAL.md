# Cambios realizados en la GUI del instalador

Archivo modificado:

- `scripts/instalador-gui.ps1`

## Alcance

- Se rediseñó únicamente la interfaz gráfica del instalador.
- No se modificó la lógica de instalación, despliegue, Cloudflare, D1, secretos, foros, cuentas adicionales ni progreso.
- Se conservaron los nombres de variables y funciones usados por el backend, incluyendo `projectName`, `timezone`, `adminKey`, `mainUser`, `mainPass`, `forumsGrid`, `accountsGrid`, `logBox`, `installButton`, `closeButton`, `Append-Log`, `Run-Command`, `Ensure-NodeTools`, `Execute-Sql` y `Put-Secret`.

## Diseño visual

- Se aplicó una apariencia profesional inspirada en Win11/Office.
- Se usó una paleta azul y blanca tomada de la imagen de referencia:
  - azul principal para cabecera, acciones y cabeceras de tablas;
  - azul claro para avisos informativos;
  - fondo gris muy claro para superficie general;
  - tarjetas blancas con borde suave para agrupar información.
- Se añadió una cabecera superior con título, subtítulo e icono visual moderno.
- Se añadieron iconos Unicode modernos en pestañas, botón de instalación y aviso informativo, compatibles con Windows Forms sin dependencias externas.

## Responsive

- La ventana usa `ClientSize`, `MinimumSize`, `Anchor`, `Dock` y tarjetas ancladas para evitar cortes en 1366x768 y resoluciones superiores.
- El área inferior de botones se separó en un panel fijo (`bottomPanel`) para que `Instalar` y `Cerrar` permanezcan visibles.
- Las pestañas y tablas mantienen anclaje en los cuatro lados para crecer o reducirse con la ventana.
- La pestaña Proyecto mantiene `AutoScroll` para resoluciones bajas sin ocultar campos.

## Controles conservados

- Se conservaron todos los campos existentes:
  - nombre técnico del proyecto;
  - zona horaria;
  - clave administrativa del panel;
  - opción para ocultar clave;
  - cuenta publicadora principal;
  - contraseña de la cuenta principal;
  - tabla de foros;
  - tabla de cuentas adicionales;
  - registro de progreso.
- En cuentas adicionales se simplificó la tabla a `Usuario Foroactivo` y `Contraseña`; el usuario se usa automáticamente como etiqueta visible y para generar la clave interna del Secret.
- Se conservaron todos los botones existentes:
  - `Instalar`;
  - `Cerrar`.
- Se añadió el botón `Mantenimiento` para cambios posteriores a la instalación.
- Se conservaron todas las pestañas funcionales:
  - Proyecto;
  - Foros;
  - Cuentas adicionales;
  - Progreso.

## Autoría y condiciones

- Se añadió un bloque visible de `Autoría y condiciones de uso` en la pestaña Proyecto.
- Texto añadido:
  - Proyecto de Código Abierto, desarrollado con ChatGPT + la consola de Firefox, con la supervisión total y múltiples pruebas de Jucarese, Administrador de Foroactivo. © 2026.
  - Aviso de derechos reservados y prohibición de reproducción, distribución, modificación o difusión sin autorización expresa.

## Mejoras de usabilidad

- Los campos se agruparon en tarjetas:
  - Autoría y condiciones;
  - Datos generales del proyecto;
  - Acceso al panel de control;
  - Cuenta publicadora principal;
  - Aviso informativo.
- Las tablas de foros y cuentas adicionales recibieron cabeceras azules, filas alternas y selección más clara.
- El progreso usa una barra visual, una lista de pasos con checks verdes y un área de log técnica secundaria.
- Se añadió aviso bajo la clave administrativa recordando que debe guardarse para entrar después en el panel de control.
- Al terminar la instalación se muestra una ventana con la URL del Worker, aviso de guardarla, botón para copiarla y botón para abrir los archivos de Foroactivo.
- Al finalizar se prepara la carpeta `INSTALAR_EN_FOROACTIVO` con:
  - `FORMULARIO_DE_PROGRAMACION.html`;
  - `PANEL_DE_CONTROL.html`;
  - `INSTRUCCIONES_DE_INSTALACION.txt`.
- El archivo de instrucciones explica dónde pegar cada código HTML, dónde usar la URL del Worker y cuándo usar la clave administrativa.
- Se añadió el icono personalizado en la ventana del instalador.
- El instalador ejecutable se genera como aplicación Windows sin ventana CMD.
- El ejecutable ya no extrae el proyecto en AppData: crea una carpeta `Gestor_Publicaciones_Foroactivo` junto al `.exe`.
- Si esa carpeta ya existe, no se sobrescribe, para conservar la configuración del Worker ya instalado.

## Mantenimiento posterior

- El botón `Mantenimiento` permite actualizar una instalación existente sin repetir todo el proceso.
- Este modo no crea de nuevo el Worker, no crea D1 y no aplica migraciones.
- Solo comprueba Node.js, dependencias y sesión de Cloudflare.
- Si se rellena la clave administrativa del panel, actualiza el Secret `ADMIN_API_KEY`.
- Si se rellenan usuario y contraseña de la cuenta publicadora principal, actualiza los Secrets:
  - `FOROACTIVO_USERNAME`;
  - `FOROACTIVO_PASSWORD`.
- Al actualizar la cuenta principal, también actualiza el registro `default` en D1 para que el formulario muestre el nuevo usuario.
- Para foros, inserta o actualiza registros en D1.
- Para cuentas adicionales, crea o actualiza los Secrets:
  - `FOROACTIVO_USERNAME_<CLAVE>`;
  - `FOROACTIVO_PASSWORD_<CLAVE>`.
- También registra la cuenta en D1 para que aparezca en la configuración pública usada por el formulario.
- Si no se rellena ningún dato de mantenimiento, muestra un aviso y no ejecuta cambios.

## Archivos HTML

- Se añadió un comentario de autoría y condiciones de uso al inicio de:
  - `panel/panel-control.html`;
  - `panel/formulario-programacion.html`.

## Compatibilidad

- Se mantiene Windows Forms.
- Se mantiene PowerShell.
- No se añadieron librerías externas.
- No se cambiaron los comandos de instalación ni despliegue; solo se añadió captura de salida en `Run-Command` para poder mostrar la URL del Worker al finalizar.

## Multilenguaje

- Se añadió selector de idioma en el encabezado del instalador.
- Idiomas disponibles:
  - Español;
  - English;
  - Português;
  - Italiano;
  - Русский;
  - Français;
  - Deutsch;
  - Română.
- El selector traduce las pestañas, títulos principales, ayudas, botones y estados principales.
- Al finalizar la instalación se generan instrucciones en todos los idiomas dentro de `INSTALAR_EN_FOROACTIVO`.
- Se mantiene `INSTRUCCIONES_DE_INSTALACION.txt` en español como archivo principal, y se añaden archivos específicos para EN, PT, IT, RU, FR, DE y RO.

## Correcciones multilenguaje de HTML

- El formulario generado traduce también comentarios HTML, comentarios CSS y comentarios JavaScript según el idioma elegido.
- Se neutralizaron identificadores internos del formulario que estaban en español:
  - `fa-programador-publicaciones` pasó a `fa-topic-scheduler`;
  - `fa-prog-destino` pasó a `fa-prog-target`;
  - `fa-prog-fecha` pasó a `fa-prog-date`;
  - `fa-prog-hora` pasó a `fa-prog-hour`;
  - `fa-prog-minuto` pasó a `fa-prog-minute`;
  - `fa-prog-boton` pasó a `fa-prog-submit`;
  - `fa-prog-estado` pasó a `fa-prog-status`.
- Se mantuvo compatibilidad con enlaces antiguos que usaban el parámetro `volver`, aunque el formulario también acepta `return`.
- Se tradujeron mensajes internos del formulario como:
  - carga del editor;
  - carga de Servimg;
  - errores de configuración;
  - guardado de programación;
  - búsqueda de emoticonos.
- Se verificaron muestras locales de formulario para ES, EN, PT, IT, RU, FR, DE y RO.

## Correcciones v22

- Se eliminó el botón externo de smileys del formulario de programación.
- Los smileys quedan integrados en el botón nativo del SCEditor de Foroactivo.
- Se añadió recepción de URLs devueltas por Servimg para insertar automáticamente la imagen como BBCode `[img]...[/img]` en el editor.
- Se mantiene un panel Servimg auxiliar para los casos en que el comando nativo no pueda abrirse dentro de una página HTML.
- Se añadió aviso en la sección de fecha y hora indicando que el cron de Cloudflare puede ejecutarse unos segundos después del minuto exacto.
- El panel de control refresca automáticamente la lista cada 15 segundos mientras está abierto.
- Se traduce en el panel el error de clave administrativa devuelto por el Worker, para evitar mezclas de español en instalaciones de otros idiomas.
- Se añadieron traducciones de las nuevas frases en ES, EN, PT, IT, RU, FR, DE y RO.

## Correcciones v23

- El instalador prepara la base D1 antes del primer `wrangler deploy`.
- Si ya existe una D1 con el nombre técnico del proyecto, se reutiliza y se escribe su `database_id` en `wrangler.jsonc`.
- Si no existe, el instalador intenta crearla y guardar el `database_id` antes de publicar el Worker.
- Si Cloudflare informa que la cuenta alcanzó el máximo de bases D1, el instalador detiene la instalación con un aviso claro antes de publicar nada.
- Esto evita el fallo en `Publish the Worker` donde Wrangler intentaba provisionar una D1 nueva sin ID y devolvía el límite máximo de D1.

## Correcciones v24

- Se amplió el mensaje de diagnóstico cuando Cloudflare devuelve límite de D1.
- El aviso aclara que borrar el Worker no borra necesariamente las bases D1, porque D1 se gestiona aparte en Cloudflare.
- El log indica explícitamente cuando Wrangler no encuentra una D1 existente con el nombre del proyecto y va a intentar crear una nueva.
- El mensaje recomienda comprobar que Wrangler esté autenticado en la misma cuenta de Cloudflare que se está revisando en el panel web.

## Correcciones v25

- La creación automática de D1 usa jurisdicción explícita `eu`.
- Se evita el fallo de Wrangler donde `--json` se interpretaba como argumento extra cuando no se indicaba jurisdicción.
- El log muestra que la nueva D1 se está creando en jurisdicción EU.

## Correcciones v26

- Se elimina `--json` del comando `wrangler d1 create`, porque esta versión de Wrangler no lo acepta en la creación de D1.
- El instalador sigue extrayendo el `database_id` desde la salida normal de Wrangler.
- Se mantiene `--jurisdiction eu` para que Wrangler no pida ubicación de forma interactiva.

## Correcciones v27

- Se añade el comando `emoticon` dentro de la barra nativa de SCEditor.
- Los smileys vuelven a aparecer dentro del editor, sin usar un botón externo separado.
- Se ajusta el estilo del desplegable de emoticonos para que las imágenes no queden comprimidas.

## Correcciones v28

- Se corrige el cierre HTML del bloque de configuración inicial del formulario.
- Los botones `Actualizar listas`, `Cancelar` y `Guardar configuración` quedan dentro del contenedor correcto.
- Se refuerzan los eventos de esos botones con `preventDefault` y `stopPropagation`.
- Se añade un respaldo por delegación de clic para que funcionen aunque Foroactivo ajuste el HTML pegado.

## Correcciones v29

- El botón `Guardar configuración` guarda y cierra inmediatamente la configuración del formulario.
- Si la carga de foros/cuentas falla, la URL del Worker y el nombre del proyecto quedan guardados y se muestra un aviso claro.
- El campo de zona horaria del instalador pasa a ser un desplegable editable.
- El desplegable horario incluye la lista IANA completa del archivo `Time zone.txt`.

## Correcciones v30

- Se regraba `scripts/instalador-gui.ps1` como UTF-8 con BOM para compatibilidad con Windows PowerShell 5.1.
- Esto corrige el problema de la v29 donde el EXE no abría porque Windows PowerShell leía caracteres acentuados como ANSI y rompía el parseo del script.

## Correcciones v31

- Se añaden reintentos automáticos a las operaciones `wrangler d1 execute`.
- El instalador detecta el timeout transitorio de Cloudflare D1 `code: 7429` y vuelve a intentar la operación antes de mostrar error.
- Los reintentos usan espera progresiva para evitar que un microcorte de la API de Cloudflare interrumpa el registro de foros o cuentas publicadoras.
- Si Cloudflare sigue fallando tras varios intentos, el instalador muestra un aviso más claro indicando que puede repetirse la instalación o usar Mantenimiento si el Worker y la D1 ya se crearon.

## Correcciones v32

- Se corrige el orden de traducción del HTML generado: primero se sustituyen frases completas y después se aplica el nombre internacional de la plataforma.
- Esto evita que frases españolas que contienen `Foroactivo` queden sin traducir tras convertirse a `Forumotion`, `Forumactif`, `Forumieren`, etc.
- Se añaden traducciones para mensajes internos del formulario que aún podían quedar en inglés:
  - configuración guardada y carga de listas;
  - configuración guardada con error al cargar listas;
  - error al abrir Servimg.
- Se generaron muestras locales del formulario en ES, EN, PT, IT, RU, FR, DE y RO y se comprobaron contra frases mezcladas habituales.

## Correcciones v33

- Se añade un manejador de clic propio para los emoticonos del desplegable de SCEditor.
- Si SCEditor muestra los smileys pero no les asigna `onclick`, el formulario detecta el clic sobre la imagen, busca su código en `window.smileys` y lo inserta en el editor.
- El respaldo funciona con `alt`, `title`, atributos `data-*` o comparación directa de la URL de la imagen.
- Se mantiene el comportamiento existente de Servimg para insertar imágenes subidas como BBCode `[img]...[/img]`.

## Correcciones v34

- El botón de emoticonos de SCEditor queda interceptado y abre un panel propio del formulario.
- Cada smiley se renderiza como botón real y al pulsarlo inserta su código directamente en el editor.
- Se capturan `pointerdown`, `mousedown`, `touchstart` y `click` para evitar que SCEditor bloquee el evento antes de insertar.
- Se añade protección para no insertar dos veces el mismo smiley cuando el navegador dispara varios eventos seguidos.
- El desplegable de colores se limita con altura máxima, scroll interno y distribución en rejilla para evitar listas largas hacia abajo.

## Correcciones v35

- Se ajusta el selector nativo de color de SCEditor (`sceditor-color-native-section`, `sceditor-color-pipette` e `input[type=color]`).
- El contenedor del selector de color recibe una clase propia `fa-color-dropdown` al abrirse para forzar anchura, altura máxima y scroll interno.
- Se mantiene visible la pipeta/color nativo sin que rompa el layout vertical del desplegable.

## Correcciones v36

- Se elimina `emoticon` de la barra nativa de SCEditor para evitar el desplegable que desaparecía al soltar el botón.
- Se añade un panel lateral propio de emoticonos junto al editor.
- El panel lateral incluye buscador por código y botones reales para insertar emoticonos directamente en el contenido.
- El panel se inicializa al arrancar el formulario y también después de cargar SCEditor.
- El título del panel se traduce en los HTML generados por idioma.

## Correcciones v38

- Se elimina el fondo azul de los botones del panel lateral de emoticonos.
- Se anula la regla general de botones del formulario para que los emoticonos no hereden el degradado azul.
- El panel de emoticonos queda con fondo blanco, botones transparentes y hover gris suave.
- El ajuste se aplica a todos los formularios generados por idioma.

## Correcciones v39

- Se elimina la línea extra de copyright del comentario inicial de los HTML generados.
- El bloque de autoría conserva una sola línea legal completa con desarrollador, plataforma Foroactivo y condiciones de uso.
- El cambio se aplica a todos los formularios generados por idioma.

## Correcciones v40

- La línea inicial `Generated language` del comentario HTML se traduce según el idioma generado.
- Los comentarios HTML técnicos se normalizan para conservar la palabra `Foroactivo` fija en todos los idiomas.
- El texto visible de la interfaz mantiene la marca localizada correspondiente a cada idioma.
- Se verificaron los comentarios de los formularios ES, EN, PT, IT, RU, FR, DE y RO para evitar marcas traducidas dentro de comentarios.

## Correcciones v41

- Los emoticonos del panel lateral se insertan como imagen BBCode `[img]...[/img]` en lugar de insertar solo el código `:smile:`.
- Antes de insertar un emoticono se intenta limpiar el formato activo del editor para que un color seleccionado no afecte al siguiente contenido.
- Se mantienen espacios alrededor del emoticono insertado para evitar que quede pegado al texto anterior o posterior.
- El cambio evita que, después de escribir texto coloreado, los emoticonos se publiquen como códigos coloreados.

## Correcciones v42

- Se limita el uso fijo de `Foroactivo` al bloque de autoría y condiciones.
- Los demás comentarios HTML vuelven a usar la marca correspondiente al idioma generado, como `Forumotion`, `Forumactif`, `Forumieren`, `Forumattivo`, `Forumeiros`, `Forum2x2` o `Forumgratuit`.
- Se mantienen las cabeceras de idioma traducidas introducidas en la v40.

## Correcciones v43

- En modo WYSIWYG, los emoticonos del panel lateral se insertan como imagen HTML real dentro del editor.
- SCEditor convierte esa imagen a BBCode válido al guardar, evitando que se publique como URL o texto coloreado.
- Antes y después de insertar se intenta limpiar el formato activo del editor para cortar el color heredado.
- En modo fuente se conserva el respaldo BBCode `[img]...[/img]`.

## Correcciones v44

- Las imágenes recibidas desde Servimg se insertan como imagen HTML real en modo WYSIWYG.
- Se evita que la URL o el BBCode `[img]...[/img]` hereden el color activo del texto.
- En modo fuente se mantiene el respaldo BBCode con saltos de línea alrededor.
- El comportamiento queda alineado con la inserción visual usada por los emoticonos.

## Correcciones v45

- Se añade una limpieza automática del editor WYSIWYG para detectar bloques Servimg insertados como texto:
  `[url=...][img]...[/img][/url]` y `[img]...[/img]`.
- Si Servimg inserta el BBCode directamente, el formulario lo convierte en imagen visible dentro del editor.
- La limpieza se ejecuta tras mensajes/callbacks de Servimg, periódicamente mientras el formulario está abierto y justo antes de leer el contenido para enviarlo.
- Esto evita que los BBCode de Servimg queden coloreados o se publiquen como texto.

## Correcciones v46

- Se actualiza la frase principal de autoría y condiciones para indicar el uso de ChatGPT y la consola de Firefox bajo la supervisión y pruebas de Jucarese.
- El texto legal se traduce en ES, EN, PT, IT, RU, FR, DE y RO.
- Dentro del bloque de condiciones se mantiene `Foroactivo` como plataforma fija en todos los idiomas.
- Fuera de las condiciones, los comentarios técnicos y textos visibles siguen usando la plataforma localizada de cada idioma, como Forumotion, Forumactif, Forumieren, Forumattivo, Forumeiros, Forum2x2 o Forumgratuit.

## Correcciones v47

- Las imágenes de Servimg se insertan directamente como nodos de imagen dentro del área WYSIWYG del editor.
- Si el cursor está dentro del editor, la imagen se coloca en esa posición; si no, se añade al final del contenido visual.
- El respaldo BBCode `[img]...[/img]` queda reservado para el modo fuente o para navegadores donde no se pueda acceder al cuerpo visual del editor.
- Se fuerza una actualización interna del editor tras insertar la imagen para evitar que el WYSIWYG quede en blanco aunque el BBCode exista al cambiar de modo.

## Correcciones v48

- Se adapta la inserción de imágenes al comportamiento real de Foroactivo: primero se pasa `[img]URL[/img]` al SCEditor para que el plugin BBCode lo convierta en imagen visible.
- El botón nativo de imagen queda interceptado por el formulario para pedir la URL y usar el mismo flujo que Servimg.
- Se mantiene la inserción visual manual solo como respaldo si SCEditor no acepta el BBCode.
- Se normalizan URLs escapadas, con `&amp;`, barras escapadas o restos de BBCode antes de insertarlas.

## Correcciones v50

- Se compara el formulario con el código fuente real de una página de nuevo tema de Foroactivo con SCEditor y Servimg activos.
- Se mantiene la carga del plugin oficial `SCEditor/src/plugins/bbcode.js` antes de los comandos del editor.
- Se protege el nombre interno `showStatus` para que la traducción de `Status` no cambie funciones JavaScript.
- Se corrigen cadenas traducidas con apóstrofes, como francés, para que no rompan el JavaScript generado.
- Se valida con `node --check` el JavaScript generado de los ocho formularios por idioma.

## Correcciones v51

- El botón de imagen abre un desplegable propio con los campos `URL`, ancho opcional, altura opcional e insertar, siguiendo la interfaz de Foroactivo.
- Se elimina el diálogo simple tipo `prompt` para que el flujo sea visual y similar al editor real.
- Al indicar ancho o altura, se genera el BBCode oficial de Foroactivo: `[img(100px,auto)]URL[/img]`, `[img(auto,120px)]URL[/img]` o `[img(100px,120px)]URL[/img]`.
- Las etiquetas del desplegable se traducen por idioma mediante marcadores internos para no romper nombres de funciones JavaScript.

## Correcciones v52

- Se añade al panel de control un botón `Ver foro` junto a `Cerrar sesión`, traducido en ES, EN, PT, IT, RU, FR, DE y RO.
- El botón del panel usa `return` o `volver` si la página llega desde el foro; si no existe esa referencia, vuelve al índice `/`.
- El formulario español conserva el botón de retorno original al tema de origen.
- Los formularios no españoles cambian el retorno al índice del foro y actualizan el texto del botón y del aviso posterior al guardado para reflejarlo.
- Se valida el JavaScript generado de los 8 formularios y los 8 paneles localizados.

## Correcciones v53

- El script del instalador se guarda como UTF-8 con BOM para que Windows PowerShell 5.1 no corrompa textos traducidos ni símbolos.
- El lanzador del EXE usa PowerShell 7 si está instalado y conserva Windows PowerShell como respaldo.

## Correcciones v54

- Los HTML generados guardan la URL del Worker instalada en `INSTALLED_WORKER_URL`.
- Si el navegador conserva una URL vieja en `localStorage`, el formulario y el panel la sustituyen automáticamente por la URL recién instalada.
- Cuando cambia la URL instalada, el formulario limpia la caché de foros/cuentas para recargarla desde el Worker correcto.
- Cuando cambia la URL instalada, el panel elimina la huella local de sesión administrativa para pedir de nuevo la clave contra el Worker correcto.

## Correcciones v55

- El botón `Actualizar listas` del formulario guarda primero la URL del Worker escrita en ajustes antes de consultar el Worker.
- La descarga de listas fuerza una URL sin caché con marca temporal para evitar datos antiguos del navegador.
- El botón muestra estado de carga y queda desactivado hasta que termina la petición.
- Se centraliza el refresco en una sola función para evitar llamadas duplicadas del mismo clic.

## Correcciones v86

- El instalador fuerza UTF-8 al leer la salida de Wrangler, evitando textos corruptos como `aplicaci├│n` cuando la D1 devuelve nombres con acentos.
- También fuerza UTF-8 al enviar texto por entrada estándar a procesos externos cuando la versión de PowerShell lo permite.
- Se configuran variables de entorno para que Node, npm y Wrangler eviten conversiones de consola antiguas y códigos de color innecesarios.
- Se limpian secuencias de control ANSI antes de mostrar o guardar la salida técnica en el registro del instalador.
- Los nombres visibles de foros y cuentas se conservan tal como se escriben, incluidos acentos, apóstrofes y signos; solo las claves internas de secretos siguen normalizándose para cumplir las reglas de Cloudflare.

## Correcciones v87

- Mantenimiento busca la identidad de instalación en más carpetas cercanas al EXE y en las carpetas finales por idioma, no solo en la carpeta activa del instalador.
- Si falta el archivo `.foroactivo-installation.json`, mantenimiento puede reconstruir el Worker desde los TXT o HTML generados por la instalación.
- Las nuevas instalaciones escriben también el nombre de la base D1 en el TXT de instrucciones para que mantenimiento pueda recuperarlo aunque se pierda el JSON oculto.
- La reconstrucción evita usar la D1 de plantilla del paquete limpio cuando no pertenece al Worker instalado.

## Correcciones v88

- El instalador registra los procesos que abre para Node.js, npm, npx, Wrangler y herramientas auxiliares.
- Al cerrar la ventana del instalador, tanto con el botón `Cerrar` como con la X de Windows, se cierran los procesos hijos iniciados por esa sesión.
- Si el cierre ocurre durante una instalación o mantenimiento, el bucle de progreso deja de esperar y no muestra un error falso por haber detenido Node.js a propósito.

## Correcciones v89

- La instalación nueva ya no pregunta si se desea usar una sesión Wrangler existente.
- Antes de autorizar Cloudflare en una instalación nueva, el instalador ejecuta cierre de sesión técnico de Wrangler.
- Se abre una única página de cierre/inicio de sesión de Cloudflare para poder elegir la cuenta correcta y después se lanza la autorización de Wrangler.
- Mantenimiento conserva el flujo anterior para no romper una instalación ya vinculada a una cuenta concreta.

## Correcciones v90

- La instalación nueva deja de abrir la página manual de logout/login de Cloudflare antes de `wrangler login`.
- El cierre de sesión técnico de Wrangler se mantiene, pero solo se abre la pestaña de autorización que lanza Wrangler.
- Esto evita que aparezcan dos pestañas de Cloudflare durante una instalación nueva.

## Correcciones v91

- El flujo de Cloudflare deja de mostrar preguntas repetidas de sesión durante mantenimiento.
- `Actualizar instalación`, cargar datos, eliminar foros y eliminar cuentas reutilizan la sesión Wrangler activa si ya existe.
- Si Wrangler ya se verificó una vez durante la ejecución del instalador, se reutiliza ese resultado y no se vuelve a abrir login.
- Se elimina el bloqueo previo por `account_id` guardado para evitar falsos errores cuando Worker y D1 son correctos pero la identidad antigua no coincide.
- La comprobación real de mantenimiento pasa a ser la respuesta de la D1 vinculada.

## Correcciones v92

- La autorización de Cloudflare en instalación nueva usa `wrangler login --browser=false` para evitar que Wrangler abra automáticamente el navegador normal.
- El instalador detecta el navegador predeterminado y navegadores instalados habituales para abrir la autorización con ventana privada.
- Se añaden argumentos privados para Edge, Chrome, Firefox, Brave, Vivaldi, Opera, Chromium, LibreWolf, Waterfox y Pale Moon.
- Ya no se usa el navegador normal como respaldo, para evitar reutilizar sesiones abiertas de Cloudflare.
- Si no se detecta un navegador compatible, el instalador se detiene con un aviso traducido en lugar de abrir una sesión antigua.
- Al cerrar el instalador se refuerza la limpieza de restos `node`, `npx`, `npm`, `cmd` vinculados a Wrangler o a la carpeta temporal del instalador.

## Reconstrucción limpia v92

- Se crea una base limpia separada en `work/rebuild_clean_v92_20260729`.
- La base limpia solo incluye código fuente, assets, panel, formulario, scripts, migraciones y documentación.
- No se copian carpetas generadas como `outputs`, `_installer_bootstrap`, `INSTALAR_EN_FOROACTIVO` ni archivos temporales de verificación.
- El objetivo es entregar un EXE nuevo sin restos de reconfiguraciones anteriores ni archivos de instalaciones de prueba.

## Correcciones v93

- Se elimina el perfil temporal de navegador para que Cloudflare se abra en una ventana privada del navegador real del usuario.
- La ventana privada usa el navegador predeterminado cuando se puede detectar; si no, prueba navegadores instalados habituales.
- Esto permite usar las cuentas guardadas del propio navegador sin caer en una ventana normal.
- Se mantienen los avisos traducidos cuando no se encuentra un navegador compatible con modo privado.

## Correcciones v95

- Antes de abrir la autorización, el instalador abre Cloudflare logout en ventana privada para cerrar cualquier cuenta privada ya activa.
- Después espera unos segundos y lanza la autorización de Wrangler en la misma modalidad privada del navegador del usuario.
- Esto evita que una sesión privada anterior vuelva a autorizar automáticamente la cuenta equivocada.


## Correcciones v96

- La autorización de Cloudflare deja de usar el puerto fijo `localhost:8976`.
- Antes de lanzar `wrangler login`, el instalador busca un puerto local libre y lo pasa a Wrangler con `--callback-port`.
- Se elimina `--callback-host=0.0.0.0` para que Wrangler use el enlace local normal del equipo.
- La detección de errores reconoce ahora cualquier `localhost:PUERTO`, no solo `localhost:8976`.


## Correcciones v97

- Se revierte el puerto dinámico porque Wrangler 4.116 informa que Cloudflare siempre redirige a `localhost:8976`.
- Antes del login se libera el puerto local 8976 si quedó ocupado por un proceso anterior de Node, npm, npx, cmd o PowerShell.
- El login vuelve a ejecutarse como `wrangler login --browser=false`, dejando que Wrangler use su callback local estándar.


## Correcciones v98

- Se elimina la apertura previa de `https://dash.cloudflare.com/logout` en ventana privada.
- La instalación nueva vuelve a abrir una sola ventana/pestaña de Cloudflare: la autorización real de Wrangler.
- Se mantiene la limpieza del puerto local 8976 antes de iniciar `wrangler login --browser=false`.


## Correcciones v99

- Se neutraliza la función antigua de cambio de cuenta para que ya no abra `dash.cloudflare.com/logout`.
- Se elimina cualquier ruta residual que pudiera abrir una segunda pestaña privada antes de la autorización real.


## Correcciones v100

- Se elimina definitivamente cualquier llamada residual a `dash.cloudflare.com/logout` del instalador.
- El flujo de Cloudflare queda reducido a una sola apertura de navegador: la URL OAuth real emitida por Wrangler.


## Correcciones v101

- Se detecta el error de Cloudflare cuando la cuenta aún no tiene subdominio `workers.dev`.
- Si aparece ese caso, el instalador abre la URL de onboarding de Cloudflare y muestra un aviso claro en el idioma seleccionado.
- El aviso explica que debe crearse el subdominio `workers.dev` una sola vez y volver a ejecutar el instalador.

