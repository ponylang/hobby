use stallion = "stallion"

primitive InterceptPass
  """
  Returned by a request interceptor to pass the request through to the handler.
  """

class ref InterceptRespond
  """

  Returned by a request interceptor to short-circuit with an HTTP response.

  The handler is not created — the interceptor's response goes directly to
  the client. Use for rejections (401, 403, 413), cached responses (304),
  redirects (301, 302), or any case where the handler isn't needed.

  Build the response with `set_header()`, `add_header()`, and the status
  and body provided at construction.

  ```pony
  // Reject unauthorized
  InterceptRespond(stallion.StatusUnauthorized, "Unauthorized")

  // Short-circuit with custom headers
  InterceptRespond(stallion.StatusTooManyRequests, "Rate limited")
    .> set_header("retry-after", "60")
  ```
  """

  let _status: stallion.Status
  let _body: ByteSeq
  embed _headers: Array[(String, String)]

  new ref create(status: stallion.Status, body: ByteSeq) =>
    _status = status
    _body = body
    _headers = Array[(String, String)]

  fun ref set_header(name: String, value: String) =>
    """

    Set a response header, replacing any existing header with the same name.

    The name is lowercased for consistency with HTTP's case-insensitive
    header names.
    """

    let lower_name: String val = name.lower()
    var i: USize = 0
    while i < _headers.size() do
      try
        if _headers(i)?._1 == lower_name then
          try _headers.delete(i)? end
        else
          i = i + 1
        end
      else
        _Unreachable()
      end
    end
    _headers.push((lower_name, value))

  fun ref add_header(name: String, value: String) =>
    """

    Add a response header without removing existing entries.

    The name is lowercased for consistency. Use for multi-value headers like
    `Set-Cookie`.
    """

    _headers.push((name.lower(), value))

  // --- Package-private accessors for _Connection ---
  fun box _response_status(): stallion.Status => _status

  fun box _response_body(): ByteSeq => _body

  fun box _headers_size(): USize => _headers.size()

  fun box _header_at(i: USize): (String, String) ? => _headers(i)?

type InterceptResult is (InterceptPass | InterceptRespond)
  """

  The result of a request interceptor: either pass the request through or
  short-circuit with a response.
  """

