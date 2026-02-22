use "collections"
use stallion = "stallion"

class ref Context
  """
  Request context passed to middleware and handlers.

  Provides access to the HTTP request, route parameters, accumulated request
  body, and a key-value data map for inter-middleware communication. Call
  `respond()` or `respond_with_headers()` to send an HTTP response.

  Mutation methods (`respond`, `respond_with_headers`, `set`) require `ref`
  access. Read-only methods (`param`, `body`, `get`, `is_handled`) require only
  `box` access. This split supports the typed accessor convention: middleware
  authors provide accessor primitives that take `Context box`, letting them
  read context data without requiring write access.
  """
  let request: stallion.Request val
  let _responder: stallion.Responder
  let _params: Map[String, String] val
  let _body: Array[U8] val
  embed _data: Map[String, Any val]
  var _handled: Bool = false

  new create(
    request': stallion.Request val,
    responder': stallion.Responder,
    params': Map[String, String] val,
    body': Array[U8] val)
  =>
    request = request'
    _responder = responder'
    _params = params'
    _body = body'
    _data = Map[String, Any val]

  fun ref respond(status: stallion.Status, body': ByteSeq) =>
    """
    Send a complete response with the given status and body.

    Sets `Content-Length` automatically. If a response has already been sent,
    this call is silently ignored (the first response wins).
    """
    if not _handled then
      _handled = true
      let body_size: USize = match body'
      | let s: String val => s.size()
      | let a: Array[U8] val => a.size()
      end
      let response = stallion.ResponseBuilder(status)
        .add_header("Content-Length", body_size.string())
        .finish_headers()
        .add_chunk(body')
        .build()
      _responder.respond(response)
    end

  fun ref respond_with_headers(status: stallion.Status,
    headers: stallion.Headers val, body': ByteSeq)
  =>
    """
    Send a complete response with explicit headers and body.

    The caller is responsible for including `Content-Length` or any other
    required headers in `headers`. If a response has already been sent, this
    call is silently ignored.
    """
    if not _handled then
      _handled = true
      let builder = stallion.ResponseBuilder(status)
      for (name, value) in headers.values() do
        builder.add_header(name, value)
      end
      let response = builder
        .finish_headers()
        .add_chunk(body')
        .build()
      _responder.respond(response)
    end

  fun box is_handled(): Bool =>
    """Returns `true` if a response has already been sent."""
    _handled

  fun box param(key: String): String ? =>
    """
    Get a route parameter by name.

    Errors if the parameter does not exist. Parameter names come from route
    definitions — `:id` in `/users/:id` is accessed as `param("id")`.
    """
    _params(key)?

  fun box body(): Array[U8] val =>
    """Return the accumulated request body bytes."""
    _body

  fun ref set(key: String, value: Any val) =>
    """
    Store a value in the context data map.

    Middleware uses this to communicate with downstream middleware and
    handlers. Keys should be namespaced to the middleware (e.g.,
    `"basic_auth"`) to avoid collisions.
    """
    _data(key) = value

  fun box get(key: String): Any val ? =>
    """
    Retrieve a value from the context data map.

    Errors if the key does not exist. Middleware authors should provide typed
    accessor primitives that wrap this method with `match` to recover domain
    types.
    """
    _data(key)?
