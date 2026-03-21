use "files"
use stallion = "stallion"

actor _ServeFilesHandler is (HandlerReceiver & _FileTarget)
  """
  Handler actor for large file streaming via `ServeFiles`.

  Owns a `_FileStreamer` and forwards file chunks through `RequestHandler`.
  Implements `HandlerReceiver` for lifecycle notifications and `_FileTarget`
  for receiving file data from the streamer.
  """
  embed _handler: RequestHandler
  var _streamer: (_FileStreamer | None) = None

  new create(ctx: HandlerContext iso, file: File iso,
    status: stallion.Status,
    headers: (stallion.Headers val | None))
  =>
    _handler = RequestHandler(consume ctx)
    match _handler.start_streaming(status, headers)
    | StreamingStarted =>
      _streamer = _FileStreamer(consume file, this)
    | stallion.ChunkedNotSupported =>
      // Shouldn't happen — ServeFiles checked inline. Clean up.
      file.dispose()
      _handler.respond(stallion.StatusHTTPVersionNotSupported,
        "HTTP Version Not Supported")
    | BodyNotNeeded =>
      // HEAD — already responded, just clean up file
      file.dispose()
    end

  be _file_chunk(data: Array[U8] val) =>
    _handler.send_chunk(data)

  be _file_done() =>
    _handler.finish()

  be dispose() =>
    match _streamer
    | let s: _FileStreamer => s.dispose()
    end

  be throttled() =>
    match _streamer
    | let s: _FileStreamer => s.pause()
    end

  be unthrottled() =>
    match _streamer
    | let s: _FileStreamer => s.resume()
    end
