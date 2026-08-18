/*
 * Forumotion Scheduler
 * Versión 1.4.0
 *
 * Funciones:
 * - Recibe y guarda temas programados en D1.
 * - Ejecuta el cron según TIME_ZONE.
 * - Inicia sesión automáticamente en Foroactivo.
 * - Publica conservando íntegro el BBCode de SCEditor.
 * - Detecta topic_id, post_id y URL publicada.
 * - Evita duplicados y controla reintentos mediante MAX_ATTEMPTS.
 * - API administrativa protegida mediante ADMIN_API_KEY:
 *     POST /api/topics/cancel
 *     POST /api/topics/publish-now
 *     POST /api/topics/reschedule
 *     POST /api/topics/pause
 *     POST /api/topics/resume
 *     POST /api/topics/edit
 *     POST /api/topics/delete
 *     GET  /api/topics/list
 *     GET  /api/public-config
 *     GET  /api/debug
 */

export default {
  async fetch(request, env) {
    const corsHeaders = {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
      "Access-Control-Allow-Headers": "Content-Type, X-API-Key",
      "Content-Type": "application/json; charset=UTF-8"
    };

    if (request.method === "OPTIONS") {
      return new Response(null, {
        status: 204,
        headers: corsHeaders
      });
    }

    try {
      const url = new URL(request.url);
      const path = normalizarRuta(url.pathname);

      if (
        request.method === "GET" &&
        path === "/api/debug"
      ) {
        return await diagnosticoWorker(env, corsHeaders);
      }

      if (
        request.method === "GET" &&
        path === "/api/topics/list"
      ) {
        await comprobarApiKey(request, env);
        return await listarTemas(url, env, corsHeaders);
      }

      if (
        request.method === "GET" &&
        path === "/api/public-config"
      ) {
        return await obtenerConfiguracionPublica(
          env,
          corsHeaders
        );
      }

      if (request.method !== "POST") {
        return jsonResponse(
          {
            ok: false,
            error: "Método no permitido."
          },
          405,
          corsHeaders
        );
      }

      if (path === "/api/topics/cancel") {
        await comprobarApiKey(request, env);
        return await cancelarTema(request, env, corsHeaders);
      }

      if (path === "/api/topics/publish-now") {
        await comprobarApiKey(request, env);
        return await publicarAhora(request, env, corsHeaders);
      }

      if (path === "/api/topics/reschedule") {
        await comprobarApiKey(request, env);
        return await reprogramarTema(request, env, corsHeaders);
      }

      if (path === "/api/topics/pause") {
        await comprobarApiKey(request, env);
        return await pausarTema(request, env, corsHeaders);
      }

      if (path === "/api/topics/resume") {
        await comprobarApiKey(request, env);
        return await reanudarTema(request, env, corsHeaders);
      }

      if (path === "/api/topics/edit") {
        await comprobarApiKey(request, env);
        return await editarTema(request, env, corsHeaders);
      }

      if (path === "/api/topics/delete") {
        await comprobarApiKey(request, env);
        return await eliminarTemasPublicados(
          request,
          env,
          corsHeaders
        );
      }

      if (
        path !== "/" &&
        path !== "/api/topics/schedule"
      ) {
        return jsonResponse(
          {
            ok: false,
            error: "Ruta no encontrada."
          },
          404,
          corsHeaders
        );
      }

      const data = await request.json();

      const title = String(data.title || "").trim();
      const content = String(data.content || "").trim();
      const forumUrl = String(data.forum_url || "").trim();
      const publishAt = String(data.publish_at || "").trim();
      const author = String(data.author || "").trim();
      const returnUrl = String(data.return_url || "").trim();

      if (!title) {
        return jsonResponse(
          {
            ok: false,
            error: "Falta el título."
          },
          400,
          corsHeaders
        );
      }

      if (!content) {
        return jsonResponse(
          {
            ok: false,
            error: "Falta el contenido."
          },
          400,
          corsHeaders
        );
      }

      if (!publishAt) {
        return jsonResponse(
          {
            ok: false,
            error: "Falta la fecha de publicación."
          },
          400,
          corsHeaders
        );
      }

      if (!author) {
        return jsonResponse(
          {
            ok: false,
            error: "Falta la cuenta publicadora."
          },
          400,
          corsHeaders
        );
      }

      const destination = parseForumUrl(forumUrl);

      const insert = await env.DB.prepare(`
        INSERT INTO scheduled_topics
        (
          title,
          content,
          forum_url,
          publish_at,
          author,
          return_url
        )
        VALUES (?, ?, ?, ?, ?, ?)
      `)
        .bind(
          title,
          content,
          destination.forumUrl,
          publishAt,
          author,
          returnUrl
        )
        .run();

      return jsonResponse(
        {
          ok: true,
          message: "Tema guardado correctamente.",
          id:
            insert &&
            insert.meta &&
            insert.meta.last_row_id
              ? Number(insert.meta.last_row_id)
              : null,
          destination: {
            domain: destination.baseUrl,
            forum_id: destination.forumId
          }
        },
        200,
        corsHeaders
      );

    } catch (error) {
      const status =
        error && error.status
          ? Number(error.status)
          : 500;

      console.error(
        "[API-ERROR]",
        error && error.message
          ? error.message
          : error
      );

      return jsonResponse(
        {
          ok: false,
          error:
            error && error.message
              ? error.message
              : "Error interno del Worker."
        },
        status,
        corsHeaders
      );
    }
  },


  async scheduled(controller, env, ctx) {
    try {
      const timeZone = env.TIME_ZONE || "UTC";
      const localNow = getLocalIsoDate(timeZone);

      console.log("[CRON-001] Cron iniciado");
      console.log("[CRON-002] Zona horaria:", timeZone);
      console.log("[CRON-003] Hora utilizada:", localNow);

      const query = await env.DB.prepare(`
        SELECT
          id,
          title,
          content,
          forum_url,
          publish_at,
          author,
          status,
          attempts
        FROM scheduled_topics
        WHERE status = 'pending'
          AND publish_at <= ?
        ORDER BY publish_at ASC
        LIMIT 5
      `)
        .bind(localNow)
        .all();

      const topics = query.results || [];

      console.log(
        "[CRON-004] Temas pendientes encontrados:",
        topics.length
      );

      const sessions = {};

      for (const topic of topics) {
        await processTopic(
          topic,
          env,
          sessions,
          localNow
        );
      }

    } catch (error) {
      console.error(
        "[CRON-ERROR]",
        error && error.message
          ? error.message
          : error
      );
    }
  }
};



async function obtenerConfiguracionPublica(
  env,
  corsHeaders
) {
  const forumsResult = await env.DB.prepare(`
    SELECT
      label,
      forum_url
    FROM publication_forums
    WHERE active = 1
    ORDER BY position ASC, id ASC
  `).all();

  const accountsResult = await env.DB.prepare(`
    SELECT
      label,
      account_key
    FROM publication_accounts
    WHERE active = 1
    ORDER BY position ASC, id ASC
  `).all();

  const headers = {
    ...corsHeaders,

    /*
     * Esta configuración cambia muy poco.
     * El navegador y Cloudflare pueden reutilizarla durante 5 minutos,
     * evitando una consulta a D1 en cada apertura del formulario.
     */
    "Cache-Control":
      "public, max-age=300, s-maxage=300, stale-while-revalidate=86400"
  };

  return jsonResponse(
    {
      ok: true,

      forums: (
        forumsResult &&
        Array.isArray(forumsResult.results)
          ? forumsResult.results
          : []
      ).map(function (item) {
        return {
          name: String(item.label || ""),
          url: String(item.forum_url || "")
        };
      }),

      publishers: (
        accountsResult &&
        Array.isArray(accountsResult.results)
          ? accountsResult.results
          : []
      ).map(function (item) {
        return {
          name: String(item.label || ""),
          key: String(item.account_key || "")
        };
      }),

      cache_seconds: 300
    },
    200,
    headers
  );
}


async function diagnosticoWorker(
  env,
  corsHeaders
) {
  let databaseOk = false;
  let databaseError = null;

  try {
    await env.DB.prepare(
      "SELECT 1 AS ok"
    ).first();

    databaseOk = true;

  } catch (error) {
    databaseError =
      error && error.message
        ? error.message
        : String(error);
  }

  return jsonResponse(
    {
      ok: true,
      version: "1.3.1",
      bindings: {
        database: databaseOk,
        schedule_admin_key:
          typeof env.ADMIN_API_KEY === "string" &&
          env.ADMIN_API_KEY.length > 0,
        foroactivo_username:
          typeof env.FOROACTIVO_USERNAME === "string" &&
          env.FOROACTIVO_USERNAME.length > 0,
        foroactivo_password:
          typeof env.FOROACTIVO_PASSWORD === "string" &&
          env.FOROACTIVO_PASSWORD.length > 0,
        time_zone:
          String(env.TIME_ZONE || ""),
        max_attempts:
          Number(env.MAX_ATTEMPTS || 0)
      },
      database_error: databaseError
    },
    200,
    corsHeaders
  );
}


async function listarTemas(
  url,
  env,
  corsHeaders
) {
  const estadosPermitidos = [
    "pending",
    "paused",
    "processing",
    "published",
    "failed",
    "cancelled"
  ];

  const status = String(
    url.searchParams.get("status") || ""
  ).trim();

  let limit = Number(
    url.searchParams.get("limit") || 50
  );

  if (
    !Number.isInteger(limit) ||
    limit < 1
  ) {
    limit = 50;
  }

  if (limit > 200) {
    limit = 200;
  }

  let result;

  if (status) {
    if (!estadosPermitidos.includes(status)) {
      const error = new Error(
        "Estado no válido."
      );
      error.status = 400;
      throw error;
    }

    result = await env.DB.prepare(`
      SELECT
        id,
        title,
        content,
        forum_url,
        publish_at,
        author,
        return_url,
        status,
        topic_id,
        post_id,
        published_url,
        published_at,
        processing_at,
        attempts,
        last_error,
        created_at
      FROM scheduled_topics
      WHERE status = ?
      ORDER BY publish_at ASC, id DESC
      LIMIT ?
    `)
      .bind(status, limit)
      .all();

  } else {
    result = await env.DB.prepare(`
      SELECT
        id,
        title,
        content,
        forum_url,
        publish_at,
        author,
        return_url,
        status,
        topic_id,
        post_id,
        published_url,
        published_at,
        processing_at,
        attempts,
        last_error,
        created_at
      FROM scheduled_topics
      ORDER BY
        CASE
          WHEN status = 'pending' THEN 0
          WHEN status = 'paused' THEN 1
          WHEN status = 'processing' THEN 2
          WHEN status = 'failed' THEN 3
          WHEN status = 'published' THEN 4
          WHEN status = 'cancelled' THEN 5
          ELSE 6
        END,
        publish_at ASC,
        id DESC
      LIMIT ?
    `)
      .bind(limit)
      .all();
  }

  const topics = result.results || [];

  console.log("[ADMIN-LIST]", {
    status: status || "all",
    limit: limit,
    count: topics.length
  });

  return jsonResponse(
    {
      ok: true,
      count: topics.length,
      topics: topics
    },
    200,
    corsHeaders
  );
}

function normalizarRuta(pathname) {
  let path = String(pathname || "/").trim();

  path = path.replace(/\/{2,}/g, "/");

  if (path.length > 1) {
    path = path.replace(/\/+$/, "");
  }

  return path || "/";
}


async function comprobarApiKey(request, env) {
  const receivedHash = String(
    request.headers.get("X-API-Key") || ""
  );

  const expectedHash = await obtenerHashClaveAdministrativa(
    env
  );

  if (!expectedHash) {
    const error = new Error(
      "Falta configurar el Secret ADMIN_API_KEY."
    );
    error.status = 500;
    throw error;
  }

  if (
    !receivedHash ||
    !comparacionSegura(
      receivedHash,
      expectedHash
    )
  ) {
    const error = new Error(
      "Contraseña no válida."
    );
    error.status = 401;
    throw error;
  }
}


async function obtenerHashClaveAdministrativa(env) {
  try {
    const row = await env.DB.prepare(`
      SELECT setting_value
      FROM admin_settings
      WHERE setting_key = 'admin_key_hash'
      LIMIT 1
    `).first();

    if (
      row &&
      typeof row.setting_value === "string" &&
      /^[a-f0-9]{64}$/i.test(row.setting_value)
    ) {
      return row.setting_value.toLowerCase();
    }
  } catch (ignore) {
    /*
     * Compatibilidad con instalaciones antiguas:
     * si la migración D1 aún no existe, se usa el Secret.
     */
  }

  const expectedRaw = String(
    env.ADMIN_API_KEY || ""
  );

  if (!expectedRaw) {
    return "";
  }

  /*
   * Normalización Unicode NFC + SHA-256.
   *
   * Esta solución admite sin problemas:
   * Ñ, ñ, tildes, diéresis, espacios y símbolos.
   *
   * La contraseña nunca se guarda en D1: solo su huella.
   */
  return await hashClave(expectedRaw);
}


async function hashClave(value) {
  const normalized = String(value).normalize("NFC");
  const bytes = new TextEncoder().encode(normalized);

  const digest = await crypto.subtle.digest(
    "SHA-256",
    bytes
  );

  return Array.from(
    new Uint8Array(digest)
  )
    .map(function (byte) {
      return byte.toString(16).padStart(2, "0");
    })
    .join("");
}

function comparacionSegura(a, b) {
  const left = String(a);
  const right = String(b);

  let difference =
    left.length ^ right.length;

  const maxLength = Math.max(
    left.length,
    right.length
  );

  for (let i = 0; i < maxLength; i++) {
    difference |=
      (left.charCodeAt(i) || 0) ^
      (right.charCodeAt(i) || 0);
  }

  return difference === 0;
}


async function leerJson(request) {
  try {
    return await request.json();
  } catch (error) {
    const invalid = new Error(
      "El cuerpo JSON no es válido."
    );
    invalid.status = 400;
    throw invalid;
  }
}


function obtenerIdTema(data) {
  const id = Number(data && data.id);

  if (
    !Number.isInteger(id) ||
    id < 1
  ) {
    const error = new Error(
      "El campo id debe ser un número entero válido."
    );
    error.status = 400;
    throw error;
  }

  return id;
}


async function obtenerTemaPorId(env, id) {
  return await env.DB.prepare(`
    SELECT
      id,
      title,
      content,
      forum_url,
      publish_at,
      author,
      return_url,
      status,
      attempts,
      topic_id,
      post_id,
      published_url,
      published_at
    FROM scheduled_topics
    WHERE id = ?
    LIMIT 1
  `)
    .bind(id)
    .first();
}


function comprobarEstadoEditable(topic) {
  if (!topic) {
    const error = new Error(
      "No existe ningún tema con ese ID."
    );
    error.status = 404;
    throw error;
  }

  if (
    topic.status !== "pending" &&
    topic.status !== "paused"
  ) {
    const error = new Error(
      "Solo se pueden modificar temas pendientes o pausados. Estado actual: " +
      topic.status
    );
    error.status = 409;
    throw error;
  }
}


async function eliminarTemasPublicados(
  request,
  env,
  corsHeaders
) {
  const data = await leerJson(request);

  const allowedStatuses = [
    "published",
    "cancelled",
    "failed"
  ];

  let ids = [];
  let statuses = [];

  if (Array.isArray(data.ids)) {
    ids = data.ids;
  } else if (data.id !== undefined) {
    ids = [data.id];
  }

  if (Array.isArray(data.statuses)) {
    statuses = data.statuses;
  } else if (data.status) {
    statuses = [data.status];
  }

  ids = ids
    .map(function (value) {
      return Number(value);
    })
    .filter(function (value) {
      return Number.isInteger(value) && value > 0;
    });

  ids = Array.from(new Set(ids));

  statuses = statuses
    .map(function (value) {
      return String(value || "").trim().toLowerCase();
    })
    .filter(function (value) {
      return allowedStatuses.indexOf(value) !== -1;
    });

  statuses = Array.from(new Set(statuses));

  if (data.all_terminal === true) {
    statuses = allowedStatuses.slice();
  }

  if (!ids.length && !statuses.length) {
    const error = new Error(
      "No se ha indicado ningún registro válido para eliminar."
    );
    error.status = 400;
    throw error;
  }

  /*
   * Seguridad:
   * solo se eliminan registros terminados:
   * published, cancelled o failed.
   *
   * Nunca se borran pending, paused o processing.
   * Esta operación solo limpia D1 y el panel.
   * No elimina temas reales de Foroactivo.
   */
  const conditions = [];
  const bindings = [];

  if (ids.length) {
    conditions.push(
      "id IN (" +
      ids.map(function () { return "?"; }).join(",") +
      ")"
    );
    bindings.push(...ids);
  }

  if (statuses.length) {
    conditions.push(
      "status IN (" +
      statuses.map(function () { return "?"; }).join(",") +
      ")"
    );
    bindings.push(...statuses);
  }

  const result = await env.DB.prepare(`
    DELETE FROM scheduled_topics
    WHERE status IN ('published', 'cancelled', 'failed')
      AND (${conditions.join(" AND ")})
  `)
    .bind(...bindings)
    .run();

  const deleted = Number(
    result &&
    result.meta &&
    result.meta.changes
      ? result.meta.changes
      : 0
  );

  console.log("[ADMIN-DELETE-TERMINAL]", {
    requestedIds: ids,
    requestedStatuses: statuses,
    deleted: deleted
  });

  return jsonResponse(
    {
      ok: true,
      message:
        deleted === 1
          ? "Registro eliminado del panel."
          : deleted + " registros eliminados del panel.",
      deleted: deleted
    },
    200,
    corsHeaders
  );
}

async function cancelarTema(
  request,
  env,
  corsHeaders
) {
  const data = await leerJson(request);
  const id = obtenerIdTema(data);
  const topic = await obtenerTemaPorId(env, id);

  comprobarEstadoEditable(topic);

  const result = await env.DB.prepare(`
    UPDATE scheduled_topics
    SET
      status = 'cancelled',
      processing_at = NULL,
      error_message = NULL,
      last_error = NULL
    WHERE id = ?
      AND status IN ('pending', 'paused')
  `)
    .bind(id)
    .run();

  if (
    !result.meta ||
    Number(result.meta.changes || 0) !== 1
  ) {
    const error = new Error(
      "No se pudo cancelar el tema porque su estado cambió."
    );
    error.status = 409;
    throw error;
  }

  console.log("[ADMIN-CANCEL]", {
    id: id,
    previousStatus: topic.status
  });

  return jsonResponse(
    {
      ok: true,
      message: "Tema cancelado correctamente.",
      id: id,
      status: "cancelled"
    },
    200,
    corsHeaders
  );
}


async function publicarAhora(
  request,
  env,
  corsHeaders
) {
  const data = await leerJson(request);
  const id = obtenerIdTema(data);
  const topic = await obtenerTemaPorId(env, id);

  comprobarEstadoEditable(topic);

  const now = getLocalIsoDate(
    env.TIME_ZONE || "UTC"
  );

  const prepared = await env.DB.prepare(`
    UPDATE scheduled_topics
    SET
      status = 'pending',
      publish_at = ?,
      processing_at = NULL,
      error_message = NULL,
      last_error = NULL
    WHERE id = ?
      AND status IN ('pending', 'paused')
  `)
    .bind(now, id)
    .run();

  if (
    !prepared.meta ||
    Number(prepared.meta.changes || 0) !== 1
  ) {
    const error = new Error(
      "No se pudo iniciar la publicación porque el estado cambió."
    );
    error.status = 409;
    throw error;
  }

  const topicToPublish = await env.DB.prepare(`
    SELECT
      id,
      title,
      content,
      forum_url,
      publish_at,
      author,
      status,
      attempts
    FROM scheduled_topics
    WHERE id = ?
    LIMIT 1
  `)
    .bind(id)
    .first();

  if (!topicToPublish) {
    const error = new Error(
      "No se pudo recuperar el tema para publicarlo."
    );
    error.status = 404;
    throw error;
  }

  console.log("[ADMIN-PUBLISH-NOW-START]", {
    id: id,
    publishAt: now
  });

  /*
   * Publicación directa:
   * no espera a la siguiente ejecución del cron.
   * Usa exactamente el mismo proceso seguro que el cron.
   */
  await processTopic(
    topicToPublish,
    env,
    {},
    now
  );

  const finalTopic = await env.DB.prepare(`
    SELECT
      id,
      status,
      published_url,
      published_at,
      error_message,
      last_error,
      attempts
    FROM scheduled_topics
    WHERE id = ?
    LIMIT 1
  `)
    .bind(id)
    .first();

  if (!finalTopic) {
    const error = new Error(
      "No se pudo comprobar el resultado de la publicación."
    );
    error.status = 500;
    throw error;
  }

  if (finalTopic.status === "published") {
    return jsonResponse(
      {
        ok: true,
        message: "Tema publicado correctamente.",
        id: id,
        status: "published",
        published_url: finalTopic.published_url,
        published_at: finalTopic.published_at,
        attempts: finalTopic.attempts
      },
      200,
      corsHeaders
    );
  }

  const error = new Error(
    finalTopic.last_error ||
    finalTopic.error_message ||
    (
      finalTopic.status === "pending"
        ? "La publicación no pudo completarse y queda pendiente para reintento."
        : "No se pudo publicar el tema."
    )
  );

  error.status =
    finalTopic.status === "pending"
      ? 409
      : 422;

  throw error;
}

async function pausarTema(
  request,
  env,
  corsHeaders
) {
  const data = await leerJson(request);
  const id = obtenerIdTema(data);

  const topic = await obtenerTemaPorId(env, id);

  if (topic.status !== "pending") {
    const error = new Error(
      "Solo se pueden pausar temas pendientes."
    );
    error.status = 409;
    throw error;
  }

  const result = await env.DB.prepare(`
    UPDATE scheduled_topics
    SET
      status = 'paused',
      processing_at = NULL
    WHERE id = ?
      AND status = 'pending'
  `)
    .bind(id)
    .run();

  if (
    !result.meta ||
    Number(result.meta.changes || 0) !== 1
  ) {
    const error = new Error(
      "No se pudo pausar el tema porque su estado cambió."
    );
    error.status = 409;
    throw error;
  }

  console.log("[ADMIN-PAUSE]", {
    id: id
  });

  return jsonResponse(
    {
      ok: true,
      message: "Tema pausado correctamente.",
      id: id,
      status: "paused"
    },
    200,
    corsHeaders
  );
}


async function reanudarTema(
  request,
  env,
  corsHeaders
) {
  const data = await leerJson(request);
  const id = obtenerIdTema(data);

  const topic = await obtenerTemaPorId(env, id);

  if (topic.status !== "paused") {
    const error = new Error(
      "Solo se pueden reanudar temas pausados."
    );
    error.status = 409;
    throw error;
  }

  const result = await env.DB.prepare(`
    UPDATE scheduled_topics
    SET
      status = 'pending',
      processing_at = NULL,
      error_message = NULL,
      last_error = NULL
    WHERE id = ?
      AND status = 'paused'
  `)
    .bind(id)
    .run();

  if (
    !result.meta ||
    Number(result.meta.changes || 0) !== 1
  ) {
    const error = new Error(
      "No se pudo reanudar el tema porque su estado cambió."
    );
    error.status = 409;
    throw error;
  }

  console.log("[ADMIN-RESUME]", {
    id: id
  });

  return jsonResponse(
    {
      ok: true,
      message: "Tema reanudado correctamente.",
      id: id,
      status: "pending"
    },
    200,
    corsHeaders
  );
}


async function reprogramarTema(
  request,
  env,
  corsHeaders
) {
  const data = await leerJson(request);
  const id = obtenerIdTema(data);
  const publishAt = String(
    data.publish_at || ""
  ).trim();

  if (!publishAt) {
    const error = new Error(
      "Falta el campo publish_at."
    );
    error.status = 400;
    throw error;
  }

  if (!esFechaProgramadaValida(publishAt)) {
    const error = new Error(
      "publish_at debe tener formato YYYY-MM-DDTHH:mm o YYYY-MM-DDTHH:mm:ss."
    );
    error.status = 400;
    throw error;
  }

  const topic = await obtenerTemaPorId(env, id);

  comprobarEstadoEditable(topic);

  const result = await env.DB.prepare(`
    UPDATE scheduled_topics
    SET
      publish_at = ?,
      status = 'pending',
      processing_at = NULL,
      error_message = NULL,
      last_error = NULL
    WHERE id = ?
      AND status IN ('pending', 'paused')
  `)
    .bind(publishAt, id)
    .run();

  if (
    !result.meta ||
    Number(result.meta.changes || 0) !== 1
  ) {
    const error = new Error(
      "No se pudo reprogramar el tema porque su estado cambió."
    );
    error.status = 409;
    throw error;
  }

  console.log("[ADMIN-RESCHEDULE]", {
    id: id,
    publishAt: publishAt
  });

  return jsonResponse(
    {
      ok: true,
      message: "Tema reprogramado correctamente.",
      id: id,
      status: "pending",
      publish_at: publishAt
    },
    200,
    corsHeaders
  );
}


async function editarTema(
  request,
  env,
  corsHeaders
) {
  const data = await leerJson(request);
  const id = obtenerIdTema(data);
  const topic = await obtenerTemaPorId(env, id);

  comprobarEstadoEditable(topic);

  const title =
    data.title === undefined
      ? topic.title
      : String(data.title || "").trim();

  const content =
    data.content === undefined
      ? topic.content
      : String(data.content || "").trim();

  const author =
    data.author === undefined
      ? topic.author
      : String(data.author || "").trim();

  const returnUrl =
    data.return_url === undefined
      ? String(topic.return_url || "")
      : String(data.return_url || "").trim();

  const publishAt =
    data.publish_at === undefined
      ? topic.publish_at
      : String(data.publish_at || "").trim();

  let forumUrl = topic.forum_url;

  if (data.forum_url !== undefined) {
    forumUrl = parseForumUrl(
      String(data.forum_url || "").trim()
    ).forumUrl;
  }

  if (!title) {
    const error = new Error(
      "El título no puede quedar vacío."
    );
    error.status = 400;
    throw error;
  }

  if (!content) {
    const error = new Error(
      "El contenido no puede quedar vacío."
    );
    error.status = 400;
    throw error;
  }

  if (!author) {
    const error = new Error(
      "La cuenta publicadora no puede quedar vacía."
    );
    error.status = 400;
    throw error;
  }

  if (
    !publishAt ||
    !esFechaProgramadaValida(publishAt)
  ) {
    const error = new Error(
      "publish_at debe tener formato YYYY-MM-DDTHH:mm o YYYY-MM-DDTHH:mm:ss."
    );
    error.status = 400;
    throw error;
  }

  const result = await env.DB.prepare(`
    UPDATE scheduled_topics
    SET
      title = ?,
      content = ?,
      forum_url = ?,
      publish_at = ?,
      author = ?,
      return_url = ?,
      status = 'pending',
      processing_at = NULL,
      error_message = NULL,
      last_error = NULL
    WHERE id = ?
      AND status IN ('pending', 'paused')
  `)
    .bind(
      title,
      content,
      forumUrl,
      publishAt,
      author,
      returnUrl,
      id
    )
    .run();

  if (
    !result.meta ||
    Number(result.meta.changes || 0) !== 1
  ) {
    const error = new Error(
      "No se pudo editar el tema porque su estado cambió."
    );
    error.status = 409;
    throw error;
  }

  console.log("[ADMIN-EDIT]", {
    id: id,
    publishAt: publishAt,
    forumUrl: forumUrl
  });

  return jsonResponse(
    {
      ok: true,
      message: "Tema actualizado correctamente.",
      id: id,
      status: "pending",
      topic: {
        title: title,
        forum_url: forumUrl,
        publish_at: publishAt,
        author: author,
        return_url: returnUrl
      }
    },
    200,
    corsHeaders
  );
}


function esFechaProgramadaValida(value) {
  return /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(?::\d{2})?$/.test(
    String(value || "")
  );
}


async function processTopic(
  topic,
  env,
  sessions,
  localNow
) {
  const lock = await env.DB.prepare(`
    UPDATE scheduled_topics
    SET
      status = 'processing',
      processing_at = ?,
      attempts = attempts + 1,
      error_message = NULL,
      last_error = NULL
    WHERE id = ?
      AND status = 'pending'
  `)
    .bind(localNow, topic.id)
    .run();

  const changes =
    lock &&
    lock.meta &&
    Number(lock.meta.changes || 0);

  if (changes !== 1) {
    console.log(
      "[TOPIC-SKIP] El tema ya estaba siendo procesado:",
      topic.id
    );

    return;
  }

  let postRequestStarted = false;

  try {
    const destination = parseForumUrl(
      topic.forum_url
    );

    console.log("[TOPIC-001] Tema preparado:", {
      id: topic.id,
      title: topic.title,
      domain: destination.baseUrl,
      forumId: destination.forumId
    });

    const publisher =
      resolvePublisherCredentials(
        topic.author,
        env
      );

    const sessionKey =
      destination.baseUrl +
      "::" +
      publisher.username;

    let session =
      sessions[sessionKey];

    if (!session) {
      console.log(
        "[LOGIN-001] Iniciando sesión en:",
        destination.baseUrl
      );

      session = await loginForumotion(
        destination.baseUrl,
        publisher.username,
        publisher.password
      );

      sessions[sessionKey] = session;

      console.log("[LOGIN-002] Login correcto:", {
        domain: destination.baseUrl,
        username: publisher.username,
        accountKey: publisher.accountKey
      });
    }

    /*
     * A partir de este punto comienza el envío real.
     * Si después ocurre un error, no se reintentará
     * automáticamente para evitar duplicados.
     */
    postRequestStarted = true;

    const publication =
      await publishForumotionTopic(
        destination,
        topic,
        session.cookieJar
      );

    const publishedAt = getLocalIsoDate(
      env.TIME_ZONE || "UTC"
    );

    await env.DB.prepare(`
      UPDATE scheduled_topics
      SET
        status = 'published',
        published_url = ?,
        topic_id = ?,
        post_id = ?,
        published_at = ?,
        error_message = NULL,
        last_error = NULL
      WHERE id = ?
    `)
      .bind(
        publication.publishedUrl,
        publication.topicId,
        publication.postId,
        publishedAt,
        topic.id
      )
      .run();

    console.log("[PUBLISH-010] TEMA PUBLICADO:", {
      databaseId: topic.id,
      topicId: publication.topicId,
      postId: publication.postId,
      url: publication.publishedUrl
    });

  } catch (error) {
    const message =
      error && error.message
        ? error.message
        : String(error);

    const maxAttempts =
      getMaxAttempts(env);

    /*
     * El valor recibido desde D1 corresponde a los intentos
     * anteriores. El Worker ya ha incrementado attempts al
     * marcar el registro como processing.
     */
    const attemptsAfterThisRun =
      Number(topic.attempts || 0) + 1;

    let newStatus;

    /*
     * Si el POST ya se inició, puede haberse publicado aunque
     * no se detectara correctamente la respuesta.
     *
     * En ese caso se marca como failed y no se reintenta solo,
     * evitando así crear dos temas iguales.
     */
    if (postRequestStarted) {
      newStatus = "failed";

    } else if (
      attemptsAfterThisRun >= maxAttempts
    ) {
      newStatus = "failed";

    } else {
      newStatus = "pending";
    }

    await env.DB.prepare(`
      UPDATE scheduled_topics
      SET
        status = ?,
        error_message = ?,
        last_error = ?
      WHERE id = ?
    `)
      .bind(
        newStatus,
        message,
        message,
        topic.id
      )
      .run();

    console.error("[TOPIC-ERROR]", {
      id: topic.id,
      error: message,
      attempts: attemptsAfterThisRun,
      maxAttempts: maxAttempts,
      nextStatus: newStatus,
      postRequestStarted: postRequestStarted
    });
  }
}


async function publishForumotionTopic(
  destination,
  topic,
  cookieJar
) {
  const formUrl =
    destination.baseUrl +
    "/post?f=" +
    encodeURIComponent(destination.forumId) +
    "&mode=newtopic";

  console.log(
    "[PUBLISH-001] Abriendo formulario:",
    formUrl
  );

  const page = await fetchWithCookies(
    formUrl,
    {
      method: "GET",
      headers: browserHeaders()
    },
    cookieJar
  );

  if (!page.response.ok) {
    throw new Error(
      "No se pudo abrir el formulario. HTTP " +
      page.response.status
    );
  }

  const html = await page.response.text();

  if (looksLikeLoginForm(html)) {
    throw new Error(
      "La sesión caducó antes de abrir el formulario."
    );
  }

  const nativeForm =
    extractPublicationForm(html);

  if (!nativeForm) {
    throw new Error(
      "No se encontró el formulario nativo de publicación."
    );
  }

  console.log(
    "[PUBLISH-002] Formulario de publicación encontrado"
  );

  const actionUrl = new URL(
    nativeForm.action || formUrl,
    formUrl
  ).toString();

  const body = new URLSearchParams();

  nativeForm.fields.forEach(function (field) {
    if (!field.name) {
      return;
    }

    const lowerName =
      field.name.toLowerCase();

    if (
      lowerName === "subject" ||
      lowerName === "message" ||
      lowerName === "post"
    ) {
      return;
    }

    body.append(
      field.name,
      field.value || ""
    );
  });

  body.set(
    "subject",
    String(topic.title || "")
  );

  /*
   * El Worker no interpreta ni modifica el contenido.
   * Envía exactamente el BBCode generado por SCEditor.
   */
  body.set(
    "message",
    String(topic.content || "")
  );

  /*
   * Se usa el valor real del botón de envío del foro.
   * No depende del idioma: Enviar, Send, Envoyer, etc.
   */
  if (nativeForm.submitName) {
    body.set(
      nativeForm.submitName,
      nativeForm.submitValue || "1"
    );
  } else {
    body.set("post", "1");
  }

  console.log(
    "[PUBLISH-003] Enviando tema"
  );

  const sent = await fetchWithCookies(
    actionUrl,
    {
      method: "POST",
      headers: {
        ...browserHeaders(),
        "Content-Type":
          "application/x-www-form-urlencoded",
        "Origin": destination.baseUrl,
        "Referer": formUrl
      },
      body: body.toString()
    },
    cookieJar
  );

  const response = sent.response;
  const resultHtml = await response.text();

  if (!response.ok) {
    throw new Error(
      "El envío devolvió HTTP " +
      response.status
    );
  }

  console.log(
    "[PUBLISH-004] URLs recorridas:",
    sent.visitedUrls
  );

  console.log(
    "[PUBLISH-005] Redirecciones:",
    sent.redirectUrls
  );

  const result = detectPublishedTopic({
    finalUrl: response.url || actionUrl,
    visitedUrls: sent.visitedUrls || [],
    redirectUrls: sent.redirectUrls || [],
    html: resultHtml,
    baseUrl: destination.baseUrl
  });

  if (!result) {
    const forumError =
      extractForumError(resultHtml);

    if (forumError) {
      throw new Error(
        "Foroactivo rechazó la publicación: " +
        forumError
      );
    }

    throw new Error(
      "Foroactivo no confirmó la creación del tema."
    );
  }

  const verified = await verifyPublishedTopic(
    result,
    topic,
    cookieJar,
    destination.baseUrl
  );

  if (!verified) {
    throw new Error(
      "Se detectó una URL de tema, pero no corresponde al tema enviado."
    );
  }

  console.log(
    "[PUBLISH-006] Publicación confirmada:",
    result
  );

  return result;
}


function resolvePublisherCredentials(
  requestedAccount,
  env
) {
  const requested = String(
    requestedAccount || ""
  ).trim();

  const defaultUsername = String(
    env.FOROACTIVO_USERNAME || ""
  );

  const defaultPassword = String(
    env.FOROACTIVO_PASSWORD || ""
  );

  /*
   * Cuenta principal:
   * se usa cuando el campo está vacío, contiene "default"
   * o coincide con el nombre de usuario principal.
   */
  if (
    !requested ||
    requested.toLowerCase() === "default" ||
    requested === defaultUsername
  ) {
    if (!defaultUsername || !defaultPassword) {
      throw new Error(
        "Faltan las credenciales de la cuenta publicadora principal."
      );
    }

    return {
      accountKey: "default",
      username: defaultUsername,
      password: defaultPassword
    };
  }

  /*
   * Cuentas adicionales:
   * el identificador se convierte en un sufijo seguro.
   *
   * Ejemplo:
   *   noticias staff
   * se busca como:
   *   FOROACTIVO_USERNAME_NOTICIAS_STAFF
   *   FOROACTIVO_PASSWORD_NOTICIAS_STAFF
   */
  const suffix = normalizePublisherKey(
    requested
  );

  const usernameKey =
    "FOROACTIVO_USERNAME_" + suffix;

  const passwordKey =
    "FOROACTIVO_PASSWORD_" + suffix;

  const username = String(
    env[usernameKey] || ""
  );

  const password = String(
    env[passwordKey] || ""
  );

  if (!username || !password) {
    throw new Error(
      'No se encontraron credenciales para la cuenta publicadora "' +
      requested +
      '".'
    );
  }

  return {
    accountKey: requested,
    username: username,
    password: password
  };
}


function normalizePublisherKey(value) {
  return String(value || "")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toUpperCase()
    .replace(/[^A-Z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "");
}

async function loginForumotion(
  baseUrl,
  username,
  password
) {
  if (!username || !password) {
    throw new Error(
      "Faltan FOROACTIVO_USERNAME o FOROACTIVO_PASSWORD."
    );
  }

  const cookieJar = {};

  const loginPage = await fetchWithCookies(
    baseUrl + "/login",
    {
      method: "GET",
      headers: browserHeaders()
    },
    cookieJar
  );

  if (!loginPage.response.ok) {
    throw new Error(
      "No se pudo abrir el login. HTTP " +
      loginPage.response.status
    );
  }

  const loginHtml =
    await loginPage.response.text();

  const hiddenFields =
    extractHiddenFields(loginHtml);

  const form = new URLSearchParams();

  hiddenFields.forEach(function (field) {
    form.append(
      field.name,
      field.value
    );
  });

  form.set("username", username);
  form.set("password", password);
  form.set("login", "1");
  form.set("autologin", "on");

  const loginResult =
    await fetchWithCookies(
      baseUrl + "/login",
      {
        method: "POST",
        headers: {
          ...browserHeaders(),
          "Content-Type":
            "application/x-www-form-urlencoded",
          "Origin": baseUrl,
          "Referer": baseUrl + "/login"
        },
        body: form.toString()
      },
      cookieJar
    );

  if (!loginResult.response.ok) {
    throw new Error(
      "El login devolvió HTTP " +
      loginResult.response.status
    );
  }

  const check =
    await fetchWithCookies(
      baseUrl +
        "/profile?mode=editprofile",
      {
        method: "GET",
        headers: browserHeaders()
      },
      cookieJar
    );

  const checkHtml =
    await check.response.text();

  if (looksLikeLoginForm(checkHtml)) {
    throw new Error(
      "Foroactivo rechazó el usuario o la contraseña."
    );
  }

  return {
    baseUrl: baseUrl,
    username: username,
    cookieJar: cookieJar
  };
}


async function fetchWithCookies(
  url,
  options,
  cookieJar
) {
  let currentUrl = url;

  let currentOptions =
    Object.assign({}, options);

  const visitedUrls = [];
  const redirectUrls = [];

  let redirects = 0;

  while (redirects <= 10) {
    visitedUrls.push(currentUrl);

    const headers = new Headers(
      currentOptions.headers || {}
    );

    const cookieHeader =
      buildCookieHeader(cookieJar);

    if (cookieHeader) {
      headers.set(
        "Cookie",
        cookieHeader
      );
    }

    const response = await fetch(
      currentUrl,
      {
        method:
          currentOptions.method || "GET",
        headers: headers,
        body: currentOptions.body,
        redirect: "manual"
      }
    );

    saveResponseCookies(
      response,
      cookieJar
    );

    if (
      response.status >= 300 &&
      response.status < 400
    ) {
      const location =
        response.headers.get("Location");

      if (!location) {
        return {
          response: response,
          cookieJar: cookieJar,
          visitedUrls: visitedUrls,
          redirectUrls: redirectUrls
        };
      }

      const nextUrl = new URL(
        location,
        currentUrl
      ).toString();

      redirectUrls.push(nextUrl);
      currentUrl = nextUrl;

      if (
        response.status === 301 ||
        response.status === 302 ||
        response.status === 303
      ) {
        currentOptions = {
          method: "GET",
          headers:
            currentOptions.headers || {}
        };
      }

      redirects++;
      continue;
    }

    return {
      response: response,
      cookieJar: cookieJar,
      visitedUrls: visitedUrls,
      redirectUrls: redirectUrls
    };
  }

  throw new Error(
    "Se superó el límite de redirecciones."
  );
}


function detectPublishedTopic(data) {
  const candidates = [];

  /*
   * Solo se aceptan direcciones procedentes del resultado real
   * del envío: URL final, redirecciones HTTP o redirecciones
   * explícitas del documento.
   *
   * No se recorren todos los enlaces href del HTML porque una
   * página de Foroactivo contiene enlaces a muchos temas antiguos
   * y eso puede producir falsos positivos.
   */
  candidates.push(data.finalUrl);

  (data.redirectUrls || []).forEach(
    function (url) {
      candidates.push(url);
    }
  );

  extractConfirmationUrlsFromHtml(
    data.html,
    data.baseUrl
  ).forEach(function (url) {
    candidates.push(url);
  });

  const seen = {};

  for (const candidate of candidates) {
    if (!candidate || seen[candidate]) {
      continue;
    }

    seen[candidate] = true;

    const parsed = parseTopicReference(
      candidate,
      data.baseUrl
    );

    if (parsed) {
      return parsed;
    }
  }

  return null;
}


function extractConfirmationUrlsFromHtml(
  html,
  baseUrl
) {
  const urls = [];
  const text = String(html || "");

  const patterns = [
    /<meta[^>]+http-equiv\s*=\s*["']?refresh["']?[^>]+content\s*=\s*["'][^"']*url\s*=\s*([^"']+)["']/gi,
    /window\.location(?:\.href)?\s*=\s*["']([^"']+)["']/gi,
    /location\.replace\(\s*["']([^"']+)["']\s*\)/gi,
    /location\.assign\(\s*["']([^"']+)["']\s*\)/gi
  ];

  patterns.forEach(function (pattern) {
    let match;

    while (
      (match = pattern.exec(text)) !== null
    ) {
      if (!match[1]) {
        continue;
      }

      try {
        urls.push(
          new URL(
            decodeHtml(match[1].trim()),
            baseUrl
          ).toString()
        );
      } catch (error) {
        // Se ignoran direcciones no válidas.
      }
    }
  });

  return urls;
}


async function verifyPublishedTopic(
  publication,
  topic,
  cookieJar,
  baseUrl
) {
  if (
    !publication ||
    !publication.topicId ||
    !publication.publishedUrl
  ) {
    return false;
  }

  const check = await fetchWithCookies(
    publication.publishedUrl,
    {
      method: "GET",
      headers: browserHeaders()
    },
    cookieJar
  );

  if (!check.response.ok) {
    return false;
  }

  const html = await check.response.text();

  if (
    looksLikeLoginForm(html) ||
    extractForumError(html)
  ) {
    return false;
  }

  const expectedTitle = normalizeComparableText(
    topic.title
  );

  if (!expectedTitle) {
    return false;
  }

  const pageText = normalizeComparableText(
    decodeHtml(
      stripHtmlTags(html)
    )
  );

  return pageText.indexOf(expectedTitle) !== -1;
}


function stripHtmlTags(value) {
  return String(value || "")
    .replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi, " ")
    .replace(/<style\b[^>]*>[\s\S]*?<\/style>/gi, " ")
    .replace(/<[^>]+>/g, " ");
}


function normalizeComparableText(value) {
  return String(value || "")
    .normalize("NFC")
    .replace(/\s+/g, " ")
    .trim()
    .toLocaleLowerCase("es");
}

function parseTopicReference(
  value,
  baseUrl
) {
  if (!value) {
    return null;
  }

  let absolute;

  try {
    absolute = new URL(
      decodeHtml(String(value)),
      baseUrl
    );
  } catch (error) {
    return null;
  }

  let topicId = null;
  let postId = null;

  /*
   * Formato:
   * /t48-nombre-del-tema
   */
  let match =
    absolute.pathname.match(
      /^\/t(\d+)(?:[-/]|$)/i
    );

  if (match) {
    topicId = Number(match[1]);
  }

  /*
   * Formatos:
   * /viewtopic?t=48
   * /viewtopic.php?t=48
   */
  if (!topicId) {
    const queryTopic =
      absolute.searchParams.get("t");

    if (
      queryTopic &&
      /^\d+$/.test(queryTopic)
    ) {
      topicId = Number(queryTopic);
    }
  }

  const queryPost =
    absolute.searchParams.get("p");

  if (
    queryPost &&
    /^\d+$/.test(queryPost)
  ) {
    postId = Number(queryPost);
  }

  /*
   * Fragmentos:
   * #101
   * #p101
   */
  if (!postId && absolute.hash) {
    const hashMatch =
      absolute.hash.match(
        /^#p?(\d+)$/i
      );

    if (hashMatch) {
      postId = Number(hashMatch[1]);
    }
  }

  if (!topicId) {
    return null;
  }

  absolute.hash = postId
    ? "#" + postId
    : "";

  return {
    topicId: topicId,
    postId: postId,
    publishedUrl: absolute.toString()
  };
}


function extractUrlsFromHtml(
  html,
  baseUrl
) {
  const urls = [];
  const text = String(html || "");

  const patterns = [
    /href\s*=\s*["']([^"']+)["']/gi,
    /content\s*=\s*["'][^"']*url\s*=\s*([^"']+)["']/gi,
    /location(?:\.href)?\s*=\s*["']([^"']+)["']/gi,
    /window\.location(?:\.href)?\s*=\s*["']([^"']+)["']/gi,
    /url\s*:\s*["']([^"']+)["']/gi
  ];

  patterns.forEach(function (pattern) {
    let match;

    while (
      (match = pattern.exec(text)) !== null
    ) {
      if (!match[1]) {
        continue;
      }

      try {
        urls.push(
          new URL(
            decodeHtml(match[1].trim()),
            baseUrl
          ).toString()
        );
      } catch (ignore) {}
    }
  });

  return urls;
}


function extractPublicationForm(html) {
  const text = String(html || "");

  const formRegex =
    /<form\b([^>]*)>([\s\S]*?)<\/form>/gi;

  let match;

  while (
    (match = formRegex.exec(text)) !== null
  ) {
    const attributes = match[1] || "";
    const content = match[2] || "";

    const hasSubject =
      /name\s*=\s*["']subject["']/i
        .test(content);

    const hasMessage =
      /name\s*=\s*["']message["']/i
        .test(content);

    if (!hasSubject || !hasMessage) {
      continue;
    }

    const submit =
      extractSubmitButton(content);

    return {
      action:
        extractAttribute(
          attributes,
          "action"
        ),
      fields:
        extractFormFields(content),
      submitName:
        submit
          ? submit.name
          : "post",
      submitValue:
        submit
          ? submit.value
          : "1"
    };
  }

  return null;
}


function extractFormFields(html) {
  const fields = [];

  const inputs =
    String(html || "").match(
      /<input\b[^>]*>/gi
    ) || [];

  inputs.forEach(function (input) {
    const name =
      extractAttribute(input, "name");

    if (!name) {
      return;
    }

    const type =
      (
        extractAttribute(
          input,
          "type"
        ) || "text"
      ).toLowerCase();

    if (
      type === "submit" ||
      type === "button" ||
      type === "reset" ||
      type === "file"
    ) {
      return;
    }

    if (
      (
        type === "checkbox" ||
        type === "radio"
      ) &&
      !/\bchecked\b/i.test(input)
    ) {
      return;
    }

    fields.push({
      name: name,
      value:
        decodeHtml(
          extractAttribute(
            input,
            "value"
          ) || ""
        )
    });
  });

  return fields;
}


function extractSubmitButton(html) {
  const inputs =
    String(html || "").match(
      /<input\b[^>]*type\s*=\s*["']submit["'][^>]*>/gi
    ) || [];

  for (const input of inputs) {
    const name =
      extractAttribute(input, "name");

    if (
      name &&
      name.toLowerCase() === "post"
    ) {
      return {
        name: name,
        value:
          decodeHtml(
            extractAttribute(
              input,
              "value"
            ) || "1"
          )
      };
    }
  }

  const buttonRegex =
    /<button\b([^>]*)>([\s\S]*?)<\/button>/gi;

  let match;

  while (
    (match =
      buttonRegex.exec(
        String(html || "")
      )) !== null
  ) {
    const attributes =
      match[1] || "";

    const name =
      extractAttribute(
        attributes,
        "name"
      );

    if (
      name &&
      name.toLowerCase() === "post"
    ) {
      return {
        name: name,
        value:
          decodeHtml(
            extractAttribute(
              attributes,
              "value"
            ) ||
            stripHtml(match[2]) ||
            "1"
          )
      };
    }
  }

  return null;
}


function extractHiddenFields(html) {
  const fields = [];

  const inputs =
    String(html || "").match(
      /<input\b[^>]*type\s*=\s*["']hidden["'][^>]*>/gi
    ) || [];

  inputs.forEach(function (input) {
    const name =
      extractAttribute(input, "name");

    if (!name) {
      return;
    }

    fields.push({
      name: name,
      value:
        decodeHtml(
          extractAttribute(
            input,
            "value"
          ) || ""
        )
    });
  });

  return fields;
}


function extractForumError(html) {
  const text = String(html || "");

  const patterns = [
    /<div[^>]*class=["'][^"']*error[^"']*["'][^>]*>([\s\S]*?)<\/div>/i,
    /<p[^>]*class=["'][^"']*error[^"']*["'][^>]*>([\s\S]*?)<\/p>/i,
    /<div[^>]*class=["'][^"']*message[^"']*["'][^>]*>([\s\S]*?)<\/div>/i
  ];

  for (const pattern of patterns) {
    const match = text.match(pattern);

    if (match && match[1]) {
      return stripHtml(
        match[1]
      ).trim();
    }
  }

  return "";
}


function looksLikeLoginForm(html) {
  const text =
    String(html || "").toLowerCase();

  return (
    text.indexOf(
      'name="username"'
    ) !== -1 &&
    text.indexOf(
      'name="password"'
    ) !== -1
  );
}


function saveResponseCookies(
  response,
  cookieJar
) {
  let cookies = [];

  if (
    response.headers &&
    typeof response.headers
      .getSetCookie === "function"
  ) {
    cookies =
      response.headers.getSetCookie();

  } else {
    const header =
      response.headers.get(
        "set-cookie"
      );

    if (header) {
      cookies = splitSetCookie(header);
    }
  }

  cookies.forEach(function (fullCookie) {
    const firstPart =
      String(fullCookie || "")
        .split(";")[0];

    const separator =
      firstPart.indexOf("=");

    if (separator === -1) {
      return;
    }

    const name =
      firstPart
        .slice(0, separator)
        .trim();

    const value =
      firstPart
        .slice(separator + 1)
        .trim();

    if (!name) {
      return;
    }

    if (value === "") {
      delete cookieJar[name];
    } else {
      cookieJar[name] = value;
    }
  });
}


function splitSetCookie(header) {
  return String(header || "").split(
    /,(?=\s*[^;,=\s]+=[^;,]*)/
  );
}


function buildCookieHeader(cookieJar) {
  return Object.keys(cookieJar)
    .map(function (name) {
      return (
        name +
        "=" +
        cookieJar[name]
      );
    })
    .join("; ");
}


function parseForumUrl(value) {
  let url;

  try {
    url = new URL(
      String(value || "").trim()
    );

  } catch (error) {
    throw new Error(
      "La dirección del foro no es válida."
    );
  }

  if (
    url.protocol !== "https:" &&
    url.protocol !== "http:"
  ) {
    throw new Error(
      "La dirección debe comenzar por http:// o https://."
    );
  }

  const match =
    url.pathname.match(
      /^\/f(\d+)(?:[-/]|$)/i
    ) ||
    url.search.match(
      /[?&]f=(\d+)(?:&|$)/i
    );

  if (!match) {
    throw new Error(
      "No se pudo obtener el ID del foro."
    );
  }

  return {
    baseUrl: url.origin,
    forumId: match[1],
    forumUrl:
      url.origin +
      url.pathname +
      url.search
  };
}


function getLocalIsoDate(timeZone) {
  const parts =
    new Intl.DateTimeFormat(
      "en-GB",
      {
        timeZone: timeZone,
        year: "numeric",
        month: "2-digit",
        day: "2-digit",
        hour: "2-digit",
        minute: "2-digit",
        second: "2-digit",
        hourCycle: "h23"
      }
    ).formatToParts(new Date());

  const values = {};

  parts.forEach(function (part) {
    if (part.type !== "literal") {
      values[part.type] =
        part.value;
    }
  });

  return (
    values.year +
    "-" +
    values.month +
    "-" +
    values.day +
    "T" +
    values.hour +
    ":" +
    values.minute +
    ":" +
    values.second
  );
}


function getMaxAttempts(env) {
  const value =
    Number(env.MAX_ATTEMPTS || 3);

  if (
    !Number.isInteger(value) ||
    value < 1 ||
    value > 10
  ) {
    return 3;
  }

  return value;
}


function browserHeaders() {
  return {
    "User-Agent":
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) " +
      "AppleWebKit/537.36 (KHTML, like Gecko) " +
      "Chrome/126.0.0.0 Safari/537.36",

    "Accept":
      "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
  };
}


function extractAttribute(
  html,
  attribute
) {
  const regex = new RegExp(
    attribute +
      "\\s*=\\s*[\"']([^\"']*)[\"']",
    "i"
  );

  const match =
    String(html || "").match(regex);

  return match ? match[1] : "";
}


function decodeHtml(text) {
  return String(text || "")
    .replace(/&amp;/gi, "&")
    .replace(/&quot;/gi, '"')
    .replace(/&#39;/gi, "'")
    .replace(/&#x27;/gi, "'")
    .replace(/&lt;/gi, "<")
    .replace(/&gt;/gi, ">");
}


function stripHtml(html) {
  return decodeHtml(
    String(html || "")
      .replace(/<br\s*\/?>/gi, "\n")
      .replace(/<[^>]+>/g, " ")
      .replace(/\s+/g, " ")
  );
}


function jsonResponse(
  data,
  status,
  headers
) {
  return new Response(
    JSON.stringify(data),
    {
      status: status,
      headers: headers
    }
  );
}
