use "collections"
use stallion = "stallion"

class ref BeforeContext
  """
  Context for the middleware `before` phase.

  Runs synchronously in `_Connection` before the handler factory is called.
  Provides access to the request, route parameters, body, and a mutable data
  map for inter-middleware communication. Call `respond()` to short-circuit
  the chain (e.g., reject with 401).

  No `start_streaming()` — before-middleware produces standard responses only.
  """
  let _request: stallion.Request val
  let _params: Map[String, String] val
  let _body: Array[U8] val
  embed _data: Map[String, Any val]
  var _handled: Bool = false
  var _status: (stallion.Status | None) = None
  var _headers: (stallion.Headers val | None) = None
  var _response_body: (ByteSeq | None) = None

  new _create(request': stallion.Request val,
    params': Map[String, String] val, body': Array[U8] val)
  =>
    _request = request'
    _params = params'
    _body = body'
    _data = Map[String, Any val]

  fun ref respond(status: stallion.Status, body': ByteSeq) =>
    """
    Short-circuit the chain with a response.

    Sets `is_handled()` to `true` — the framework stops the forward phase
    and skips to after phases. First response wins.
    """
    if not _handled then
      _handled = true
      _status = status
      _response_body = body'
    end

  fun ref respond_with_headers(status: stallion.Status,
    headers: stallion.Headers val, body': ByteSeq)
  =>
    """
    Short-circuit the chain with a response including explicit headers.

    The caller is responsible for including `Content-Length` or any other
    required headers.
    """
    if not _handled then
      _handled = true
      _status = status
      _headers = headers
      _response_body = body'
    end

  fun box is_handled(): Bool =>
    """Returns `true` if `respond()` has been called."""
    _handled

  fun box request(): stallion.Request val =>
    """Return the HTTP request."""
    _request

  fun box param(key: String): String ? =>
    """
    Get a route parameter by name.

    Errors if the parameter does not exist.
    """
    _params(key)?

  fun box body(): Array[U8] val =>
    """Return the accumulated request body bytes."""
    _body

  fun ref set(key: String, value: Any val) =>
    """
    Store a value in the data map for downstream middleware and handlers.

    Keys should be namespaced to the middleware (e.g., `"basic_auth"`) to
    avoid collisions.
    """
    _data(key) = value

  fun box get(key: String): Any val ? =>
    """
    Retrieve a value from the data map.

    Errors if the key does not exist.
    """
    _data(key)?

  // --- Package-private accessors for _Connection ---

  fun box _response_status(): (stallion.Status | None) => _status
  fun box _response_headers(): (stallion.Headers val | None) => _headers
  fun box _get_response_body(): (ByteSeq | None) => _response_body
  fun ref _freeze_data(): Map[String, Any val] val =>
    """Copy the mutable data map into an immutable val map."""
    let sz = _data.size()
    let m: Map[String, Any val] iso =
      recover iso Map[String, Any val](sz) end
    for (k, v) in _data.pairs() do
      m(k) = v
    end
    consume m
