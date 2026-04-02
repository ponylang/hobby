use stallion = "stallion"

class ref _BufferedResponse
  """

  Mutable response buffer for response interceptor modification.

  Created by `_Connection` when a response is produced (from handler, request
  interceptor short-circuit, 404, timeout, or streaming completion). Response
  interceptors modify status, headers, and body via `ResponseContext`. The
  connection serializes it via `_build()` after all interceptors have run.

  Content-Length is computed automatically by `_build()` from the final body
  size, after interceptors have had a chance to modify the body. If a
  Content-Length header is already present (from explicit user headers or an
  interceptor), `_build()` does not override it.
  """

  var status: stallion.Status
  embed headers: Array[(String, String)]
  var body: (ByteSeq | None)
  let is_streaming: Bool
  let is_head: Bool

  new ref _standard(
    status': stallion.Status,
    body': ByteSeq,
    is_head': Bool)
  =>
    """
    Create a buffered response for a simple respond() call.
    """
    status = status'
    headers = Array[(String, String)]
    body = body'
    is_streaming = false
    is_head = is_head'

  new ref _with_headers(
    status': stallion.Status,
    hdrs: stallion.Headers val,
    body': ByteSeq,
    is_head': Bool)
  =>
    """
    Create a buffered response with explicit headers.
    """
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
    """
    Create a buffered response from an interceptor short-circuit.
    """
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
    body = respond._response_body()
    is_streaming = false
    is_head = is_head'

  new ref _streaming_complete(status': stallion.Status, is_head': Bool) =>
    """
    Create a buffered response for response interceptors on stream finish.
    """
    status = status'
    headers = Array[(String, String)]
    body = None
    is_streaming = true
    is_head = is_head'

  fun box _build(): Array[U8] val =>
    """

    Serialize this buffered response into HTTP bytes for the wire.

    For non-streaming responses, auto-adds Content-Length from the final body
    size if no Content-Length header is already present. This runs after all
    response interceptors, so interceptors that call `set_body()` get correct
    Content-Length automatically.
    """

    let builder = stallion.ResponseBuilder(status)
    for (name, value) in headers.values() do
      builder.add_header(name, value)
    end

    // Auto-add Content-Length for non-streaming responses
    if not is_streaming then
      var has_content_length = false
      for (n, _) in headers.values() do
        if n.lower() == "content-length" then
          has_content_length = true
          break
        end
      end
      if not has_content_length then
        let body_size: USize =
          match body
          | let s: String val => s.size()
          | let a: Array[U8] val => a.size()
          else
            0
          end
        builder.add_header("content-length", body_size.string())
      end
    end

    let body_builder = builder.finish_headers()
    if not is_head then
      match body
      | let b: ByteSeq => body_builder.add_chunk(b)
      end
    end
    body_builder.build()
