use stallion = "stallion"

class ref _BufferedResponse
  """
  Mutable response buffer for after-middleware modification.

  Created by `_Connection` when a response is produced (from before-middleware,
  handler, timeout, or streaming completion). After-middleware modifies headers
  via `AfterContext`. The connection serializes it via `ResponseBuilder` after
  the after-chain completes.
  """
  var status: stallion.Status
  embed headers: Array[(String, String)]
  var body: (ByteSeq | None)
  let is_streaming: Bool
  let is_head: Bool

  new ref _standard(status': stallion.Status, body': ByteSeq,
    is_head': Bool)
  =>
    """Create a buffered response for a simple respond() call."""
    status = status'
    headers = Array[(String, String)]
    let body_size: USize = match \exhaustive\ body'
    | let s: String val => s.size()
    | let a: Array[U8] val => a.size()
    end
    headers.push(("Content-Length", body_size.string()))
    body = body'
    is_streaming = false
    is_head = is_head'

  new ref _with_headers(status': stallion.Status,
    hdrs: stallion.Headers val, body': ByteSeq, is_head': Bool)
  =>
    """Create a buffered response with explicit headers."""
    status = status'
    headers = Array[(String, String)]
    for hdr in hdrs.values() do
      headers.push((hdr.name, hdr.value))
    end
    body = body'
    is_streaming = false
    is_head = is_head'

  new ref _from_intercept_respond(respond: InterceptRespond ref,
    is_head': Bool)
  =>
    """Create a buffered response from an interceptor short-circuit."""
    status = respond._response_status()
    headers = Array[(String, String)]
    var i: USize = 0
    while i < respond._headers_size() do
      try
        headers.push(respond._header_at(i)?)
      else
        _Unreachable()
      end
      i = i + 1
    end
    let b = respond._response_body()
    // Auto-add content-length if not explicitly set
    var has_content_length = false
    for (n, _) in headers.values() do
      if n == "content-length" then
        has_content_length = true
        break
      end
    end
    if not has_content_length then
      let body_size: USize = match \exhaustive\ b
      | let s: String val => s.size()
      | let a: Array[U8] val => a.size()
      end
      headers.push(("content-length", body_size.string()))
    end
    body = b
    is_streaming = false
    is_head = is_head'

  new ref _streaming_complete(status': stallion.Status, is_head': Bool) =>
    """Create a buffered response for after-middleware on stream finish."""
    status = status'
    headers = Array[(String, String)]
    body = None
    is_streaming = true
    is_head = is_head'

  fun box _build(): Array[U8] val =>
    """Serialize this buffered response into HTTP bytes for the wire."""
    let builder = stallion.ResponseBuilder(status)
    for (name, value) in headers.values() do
      builder.add_header(name, value)
    end
    let body_builder = builder.finish_headers()
    if not is_head then
      match body
      | let b: ByteSeq => body_builder.add_chunk(b)
      end
    end
    body_builder.build()
