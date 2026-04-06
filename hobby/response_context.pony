use stallion = "stallion"

class ref ResponseContext
  """
  Context for response interceptors.

  Provides read access to the response status, body, streaming state, and the
  original request. Write access to response headers, status, and body is
  available via `set_status()`, `set_header()`, `add_header()`, and
  `set_body()`.

  For streaming responses (`is_streaming()` is `true`), all mutations are
  silently ignored — headers and status are already on the wire, and body
  chunks have already been sent.
  """
  let _buf: _BufferedResponse ref
  let _request: stallion.Request val

  new _create(buf: _BufferedResponse ref, request': stallion.Request val) =>
    _buf = buf
    _request = request'

  fun box status(): stallion.Status =>
    """
    Return the response status.
    """
    _buf.status

  fun box body(): (ByteSeq | None) =>
    """
    Return the response body, or `None` for streaming responses.
    """
    _buf.body

  fun box is_streaming(): Bool =>
    """
    Return `true` if this was a streaming response.
    """
    _buf.is_streaming

  fun box request(): stallion.Request val =>
    """
    Return the original HTTP request.
    """
    _request

  fun ref set_status(status': stallion.Status) =>
    """
    Replace the response status.

    No-op for streaming responses (status already on wire).
    """
    if not _buf.is_streaming then
      _buf.status = status'
    end

  fun ref set_header(name: String, value: String) =>
    """
    Set or replace a response header.

    Removes any existing entries with the same name (case-insensitive per
    RFC 7230 section 3.2) and adds a new one with the name lowercased.
    No-op for streaming responses (headers already on wire).
    """
    if not _buf.is_streaming then
      let lower_name: String val = name.lower()
      var i: USize = 0
      while i < _buf.headers.size() do
        try
          if _buf.headers(i)?._1.lower() == lower_name then
            try _buf.headers.delete(i)? end
          else
            i = i + 1
          end
        else
          _Unreachable()
        end
      end
      _buf.headers.push((lower_name, value))
    end

  fun ref add_header(name: String, value: String) =>
    """
    Add a response header without removing existing entries.

    The name is lowercased for consistency. Use for multi-value headers like
    `Set-Cookie`. No-op for streaming responses.
    """
    if not _buf.is_streaming then
      _buf.headers.push((name.lower(), value))
    end

  fun ref set_body(body': ByteSeq) =>
    """
    Replace the response body.

    Content-Length is recalculated automatically at serialization time.
    No-op for streaming responses (chunks already sent).
    """
    if not _buf.is_streaming then
      _buf.body = body'
    end
