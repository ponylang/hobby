use "files"
use stallion = "stallion"

class val ServeFiles is Handler
  """
  Serve files from a directory on disk.

  Small files (below the chunk threshold) are served as a single response
  with `Content-Length`. Large files are streamed using chunked transfer
  encoding. When the client does not support chunked encoding (HTTP/1.0),
  small files are still served normally, but large files are rejected
  with 505 HTTP Version Not Supported to prevent memory exhaustion.

  HEAD requests are optimized: the handler responds with `Content-Type` and
  `Content-Length` headers without reading the file, regardless of file size.

  Routes must use `*filepath` as the wildcard parameter name:

  ```pony
  use "files"
  use hobby = "hobby"
  use stallion = "stallion"
  use lori = "lori"

  actor Main
    new create(env: Env) =>
      let auth = lori.TCPListenAuth(env.root)
      let root = FilePath(FileAuth(env.root), "./public")
      hobby.Application
        .>get("/static/*filepath", hobby.ServeFiles(root))
        .serve(auth, stallion.ServerConfig("0.0.0.0", "8080"), env.out)
  ```

  Path traversal is prevented by Pony's `FilePath.from()`, which rejects
  any resolved path that is not a child of the base directory.

  Directory requests return 404 — there is no automatic index file lookup
  (e.g., `/dir/` does not serve `/dir/index.html`).
  """
  let _root: FilePath
  let _chunk_threshold: USize

  new val create(root: FilePath, chunk_threshold: USize = 1024) =>
    """
    Create a handler that serves files under `root`.

    `root` must have `FileLookup`, `FileStat`, and `FileRead` capabilities.
    `chunk_threshold` is the file size in kilobytes at or above which
    chunked streaming is used instead of a single response. Default: 1024
    (1 MB).

    If the route uses a wildcard name other than `*filepath`, param lookup
    will fail and the handler will return 500. Always use `*filepath`.
    """
    _root = root
    _chunk_threshold = chunk_threshold * 1024

  fun apply(ctx: Context ref) ? =>
    // Extract the wildcard param — errors if not named "filepath" (500)
    let filepath = ctx.param("filepath")?

    // Resolve path safely — errors on traversal attempts
    let resolved = try
      FilePath.from(_root, filepath)?
    else
      ctx.respond(stallion.StatusNotFound, "Not Found")
      return
    end

    // Stat the file — errors if file doesn't exist
    let info = try
      FileInfo(resolved)?
    else
      ctx.respond(stallion.StatusNotFound, "Not Found")
      return
    end

    // Must be a regular file, not a directory
    if not info.file then
      ctx.respond(stallion.StatusNotFound, "Not Found")
      return
    end

    let content_type = _ContentType(Path.ext(filepath))

    // HEAD optimization: respond with headers only, skip file I/O entirely.
    // Content-Length is always set from stat size — even for files that GET
    // would stream with chunked encoding — since HEAD with Content-Length is
    // more useful to clients (e.g., checking download size) and is explicitly
    // allowed by RFC 7231 §4.3.2.
    if ctx.request.method is stallion.HEAD then
      let headers = recover val
        stallion.Headers
          .>set("Content-Type", content_type)
          .>set("Content-Length", info.size.string())
      end
      ctx.respond_with_headers(stallion.StatusOK, headers, "")
      return
    end

    if info.size < _chunk_threshold then
      // Small file: read entirely and respond with Content-Length
      let file = File.open(resolved)
      if file.errno() isnt FileOK then error end
      let body = file.read(info.size)
      file.dispose()
      let body_size = body.size()
      let headers = recover val
        stallion.Headers
          .>set("Content-Type", content_type)
          .>set("Content-Length", body_size.string())
      end
      ctx.respond_with_headers(stallion.StatusOK, headers, consume body)
    else
      // Large file: open before starting stream so failure produces 500
      let file: File iso = recover iso
        let f = File.open(resolved)
        if f.errno() isnt FileOK then error end
        f
      end

      let headers = recover val
        stallion.Headers
          .>set("Content-Type", content_type)
      end
      match ctx.start_streaming(stallion.StatusOK, headers)?
      | let sender: StreamSender tag =>
        _FileStreamer(consume file, sender)
      | stallion.ChunkedNotSupported =>
        file.dispose()
        ctx.respond(stallion.StatusHTTPVersionNotSupported,
          "HTTP Version Not Supported")
      end
    end
