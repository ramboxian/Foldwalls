export default {
  async fetch(request, env) {
    if (request.method !== "GET" && request.method !== "HEAD") {
      return new Response("Method Not Allowed", {
        status: 405,
        headers: {Allow: "GET, HEAD"},
      })
    }

    let key
    try {
      key = decodeURIComponent(new URL(request.url).pathname.replace(/^\/+/, ""))
    } catch {
      return new Response("Bad Request", {status: 400})
    }

    if (!key || key.split("/").some((segment) => segment === "..")) {
      return new Response("Not Found", {status: 404})
    }

    let object
    try {
      object =
        request.method === "HEAD"
          ? await env.MEDIA.head(key)
          : await env.MEDIA.get(key, {range: request.headers})
    } catch {
      return new Response("Range Not Satisfiable", {status: 416})
    }

    if (!object) {
      return new Response("Not Found", {status: 404})
    }

    const headers = new Headers()
    object.writeHttpMetadata(headers)
    headers.set("etag", object.httpEtag)
    headers.set("accept-ranges", "bytes")
    headers.set("cache-control", "public, max-age=31536000, immutable")
    headers.set("x-content-type-options", "nosniff")

    let status = 200
    const rangeWasRequested =
      request.method === "GET" && request.headers.has("Range")
    if (rangeWasRequested && object.range) {
      const offset = object.range.offset ?? 0
      const length = object.range.length ?? object.size
      status = 206
      headers.set(
        "content-range",
        `bytes ${offset}-${offset + length - 1}/${object.size}`,
      )
      headers.set("content-length", String(length))
    } else {
      headers.set("content-length", String(object.size))
    }

    return new Response(request.method === "HEAD" ? null : object.body, {
      status,
      headers,
    })
  },
}
