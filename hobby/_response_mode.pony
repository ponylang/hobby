use stallion = "stallion"

interface val _ResponseMode
  """
  Strategy for building HTTP responses, separating HEAD from standard behavior.

  Standard mode builds full responses with bodies. Head mode builds
  headers-only responses, suppressing bodies while preserving Content-Length.
  """
  fun respond(responder: stallion.Responder, status: stallion.Status,
    body': ByteSeq, body_size: USize)

  fun respond_with_headers(responder: stallion.Responder,
    status: stallion.Status, headers: stallion.Headers val, body': ByteSeq)

  fun start_streaming(responder: stallion.Responder, status: stallion.Status,
    headers: (stallion.Headers val | None), conn: _Connection tag)
    : (StreamSender tag | stallion.ChunkedNotSupported | BodyNotNeeded) ?

primitive _StandardResponseMode is _ResponseMode
  fun respond(responder: stallion.Responder, status: stallion.Status,
    body': ByteSeq, body_size: USize)
  =>
    let response = stallion.ResponseBuilder(status)
      .add_header("Content-Length", body_size.string())
      .finish_headers()
      .add_chunk(body')
      .build()
    responder.respond(response)

  fun respond_with_headers(responder: stallion.Responder,
    status: stallion.Status, headers: stallion.Headers val, body': ByteSeq)
  =>
    let builder = stallion.ResponseBuilder(status)
    for (name, value) in headers.values() do
      builder.add_header(name, value)
    end
    let response = builder
      .finish_headers()
      .add_chunk(body')
      .build()
    responder.respond(response)

  fun start_streaming(responder: stallion.Responder, status: stallion.Status,
    headers: (stallion.Headers val | None), conn: _Connection tag)
    : (StreamSender tag | stallion.ChunkedNotSupported | BodyNotNeeded) ?
  =>
    match \exhaustive\ responder.start_chunked_response(status, headers)
    | stallion.StreamingStarted => conn
    | stallion.ChunkedNotSupported => stallion.ChunkedNotSupported
    | stallion.AlreadyResponded => error
    end

primitive _HeadResponseMode is _ResponseMode
  fun respond(responder: stallion.Responder, status: stallion.Status,
    body': ByteSeq, body_size: USize)
  =>
    let response = stallion.ResponseBuilder(status)
      .add_header("Content-Length", body_size.string())
      .finish_headers()
      .build()
    responder.respond(response)

  fun respond_with_headers(responder: stallion.Responder,
    status: stallion.Status, headers: stallion.Headers val, body': ByteSeq)
  =>
    let builder = stallion.ResponseBuilder(status)
    for (name, value) in headers.values() do
      builder.add_header(name, value)
    end
    let response = builder
      .finish_headers()
      .build()
    responder.respond(response)

  fun start_streaming(responder: stallion.Responder, status: stallion.Status,
    headers: (stallion.Headers val | None), conn: _Connection tag)
    : (StreamSender tag | stallion.ChunkedNotSupported | BodyNotNeeded)
  =>
    // Build a headers-only response without going through
    // start_chunked_response(), which would inject Transfer-Encoding: chunked.
    let builder = stallion.ResponseBuilder(status)
    match headers
    | let h: stallion.Headers val =>
      for (name, value) in h.values() do
        builder.add_header(name, value)
      end
    end
    let response = builder
      .finish_headers()
      .build()
    responder.respond(response)
    BodyNotNeeded
