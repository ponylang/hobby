use "files"
use "collections"
use stallion = "stallion"

class val ServeFiles
  """
  Serve files from a directory on disk.

  Structurally matches `HandlerFactory` — pass directly to route methods.
  For small files, conditional requests, and HEAD, responds inline via
  `RequestHandler` and returns `None`. For large files, creates a
  `_ServeFilesHandler` actor that streams the file.

  Small files (below the chunk threshold) are served as a single response
  with `Content-Length`. Large files are streamed using chunked transfer
  encoding. When the client does not support chunked encoding (HTTP/1.0),
  small files are still served normally, but large files are rejected
  with 505 HTTP Version Not Supported to prevent memory exhaustion.

  HEAD requests are optimized: the handler responds with `Content-Type`
  and `Content-Length` headers without reading the file, regardless of
  file size.

  Responses include caching headers:

  - **ETag**: Weak ETag computed from file metadata
    (`W/"<inode>-<size>-<mtime>"`). On Windows, `FileInfo.inode` is
    always 0, reducing collision resistance to size+mtime only.
  - **Last-Modified**: RFC 7231 IMF-fixdate from the file's modification
    time.
  - **Cache-Control**: Configurable via the `cache_control` constructor
    parameter. Defaults to `"public, max-age=3600"`. Pass `None` to
    omit.

  Conditional requests are supported per RFC 7232:

  - `If-None-Match` is checked first (ETag comparison using weak
    matching).
  - `If-Modified-Since` is checked only when `If-None-Match` is absent.
  - When either matches, the handler responds with 304 Not Modified
    (cache headers included, no body).

  Custom content types can be added via the `content_types` parameter:

  ```pony
  let types = hobby.ContentTypes
    .add("webp", "image/webp")
    .add("avif", "image/avif")
  hobby.ServeFiles(root where content_types = types)
  ```

  Routes must use `*filepath` as the wildcard parameter name:

  ```pony
  use "files"
  use hobby = "hobby"
  use stallion = "stallion"
  use lori = "lori"

  actor Main is hobby.ServerNotify
    new create(env: Env) =>
      let auth = lori.TCPListenAuth(env.root)
      let root =
        FilePath(FileAuth(env.root), "./public")
      let app = hobby.Application
        .> get(
          "/static/*filepath",
          hobby.ServeFiles(root))

      match app.build()
      | let built: hobby.BuiltApplication =>
        hobby.Server(auth, built, this
          where host = "0.0.0.0", port = "8080")
      | let err: hobby.ConfigError =>
        None
      end
  ```

  Path traversal is prevented by Pony's `FilePath.from()`, which rejects
  any resolved path that is not a child of the base directory.

  When a request resolves to a directory, `ServeFiles` looks for an
  `index.html` file inside it. If found, the index file is served with the
  correct `text/html` content type and caching headers. If no `index.html`
  exists, the directory request returns 404.
  """
  let _root: FilePath
  let _chunk_threshold: USize
  let _cache_control: (String | None)
  let _content_types: ContentTypes

  new val create(
    root: FilePath,
    chunk_threshold: USize = 1024,
    cache_control: (String | None) = "public, max-age=3600",
    content_types: ContentTypes = ContentTypes)
  =>
    """
    Create a handler factory that serves files under `root`.

    `root` must have `FileLookup`, `FileStat`, and `FileRead` capabilities.
    `chunk_threshold` is the file size in kilobytes at or above which
    chunked streaming is used instead of a single response. Default: 1024
    (1 MB).

    `cache_control` sets the `Cache-Control` header value. Defaults to
    `"public, max-age=3600"` (1 hour). Pass `None` to omit the header.

    `content_types` controls the file extension to MIME type mapping.
    Defaults to a `ContentTypes` with 17 common extensions. Chain
    `.add()` calls to add custom mappings.

    If the route uses a wildcard name other than `*filepath`, param lookup
    will fail and the handler will return 500. Always use `*filepath`.
    """
    _root = root
    _chunk_threshold = chunk_threshold * 1024
    _cache_control = cache_control
    _content_types = content_types

  fun apply(ctx: HandlerContext iso): (HandlerReceiver tag | None) =>
    // Read from ctx before consuming (iso->val viewpoint adaptation).
    // All checks happen before the single consume point at the end.
    let request = ctx.request
    let params = ctx.params

    // Resolve the file action without consuming ctx
    match \exhaustive\ _resolve(request, params)
    | let r: _ServeInline =>
      _do_inline(consume ctx, r)
    | let r: _ServeStream =>
      _do_stream(consume ctx, r)
    end

  fun _do_inline(
    ctx: HandlerContext iso,
    r: _ServeInline)
    : (HandlerReceiver tag | None)
  =>
    let handler = RequestHandler(consume ctx)
    match r.headers
    | let h: stallion.Headers val =>
      handler.respond_with_headers(r.status, h, r.body)
    else
      handler.respond(r.status, r.body)
    end
    None

  fun _do_stream(
    ctx: HandlerContext iso,
    r: _ServeStream)
    : (HandlerReceiver tag | None)
  =>
    let file_result: (File iso | None) =
      try
        recover iso
          let f = File.open(r.resolved)
          if f.errno() isnt FileOK then error end
          f
        end
      else
        None
      end
    match consume file_result
    | let file: File iso =>
      _ServeFilesHandler(
        consume ctx, consume file, r.status, r.headers)
    else
      RequestHandler(consume ctx).respond(
        stallion.StatusInternalServerError,
        "Internal Server Error")
      None
    end

  fun _resolve(
    request: stallion.Request val,
    params: Map[String, String] val)
    : (_ServeInline | _ServeStream)
  =>
    let is_head = request.method is stallion.HEAD

    // Extract wildcard param
    let filepath =
      try
        params("filepath")?
      else
        return _ServeInline._error(
          stallion.StatusInternalServerError,
          "Internal Server Error")
      end

    // Resolve path safely
    var resolved =
      try
        FilePath.from(_root, filepath)?
      else
        return _ServeInline._error(
          stallion.StatusNotFound, "Not Found")
      end

    // Stat the file
    var info =
      try
        FileInfo(resolved)?
      else
        return _ServeInline._error(
          stallion.StatusNotFound, "Not Found")
      end

    // Directory → try serving index.html
    if info.directory then
      resolved =
        try
          FilePath.from(resolved, "index.html")?
        else
          return _ServeInline._error(
            stallion.StatusNotFound, "Not Found")
        end
      info =
        try
          FileInfo(resolved)?
        else
          return _ServeInline._error(
            stallion.StatusNotFound, "Not Found")
        end
    end

    // After index fallback, non-file entries still 404
    if not info.file then
      return _ServeInline._error(
        stallion.StatusNotFound, "Not Found")
    end

    let content_type = _content_types(Path.ext(resolved.path))

    // Compute cache identifiers
    (let mod_secs, _) = info.modified_time
    let etag = _ETag(info.inode, info.size, mod_secs)
    let last_modified = _HTTPDate(mod_secs)

    // Conditional request validation (RFC 7232 §3)
    let not_modified =
      match request.headers.get("if-none-match")
      | let inm: String => _ETag.matches(inm, etag)
      else
        match request.headers.get("if-modified-since")
        | let ims: String => ims == last_modified
        else
          false
        end
      end

    if not_modified then
      let headers =
        recover val
          let h = stallion.Headers
            .> set("ETag", etag)
            .> set("Last-Modified", last_modified)
          match _cache_control
          | let cc: String =>
            h .> set("Cache-Control", cc)
          end
          h
        end
      return _ServeInline._with_headers(
        stallion.StatusNotModified, headers, "")
    end

    // HEAD optimization: headers only, skip file I/O
    if is_head then
      let headers =
        recover val
          let h = stallion.Headers
            .> set("Content-Type", content_type)
            .> set("Content-Length", info.size.string())
            .> set("ETag", etag)
            .> set("Last-Modified", last_modified)
          match _cache_control
          | let cc: String =>
            h .> set("Cache-Control", cc)
          end
          h
        end
      return _ServeInline._with_headers(
        stallion.StatusOK, headers, "")
    end

    if info.size < _chunk_threshold then
      // Small file: read and respond inline
      let file =
        try
          let f = File.open(resolved)
          if f.errno() isnt FileOK then error end
          f
        else
          return _ServeInline._error(
            stallion.StatusInternalServerError,
            "Internal Server Error")
        end
      let body = file.read(info.size)
      file.dispose()
      let body_size = body.size()
      let headers =
        recover val
          let h = stallion.Headers
            .> set("Content-Type", content_type)
            .> set("Content-Length", body_size.string())
            .> set("ETag", etag)
            .> set("Last-Modified", last_modified)
          match _cache_control
          | let cc: String =>
            h .> set("Cache-Control", cc)
          end
          h
        end
      _ServeInline._with_headers(
        stallion.StatusOK, headers, consume body)
    else
      // Large file: check HTTP version first
      if request.version is stallion.HTTP10 then
        return _ServeInline._error(
          stallion.StatusHTTPVersionNotSupported,
          "HTTP Version Not Supported")
      end

      let headers =
        recover val
          let h = stallion.Headers
            .> set("Content-Type", content_type)
            .> set("ETag", etag)
            .> set("Last-Modified", last_modified)
          match _cache_control
          | let cc: String =>
            h .> set("Cache-Control", cc)
          end
          h
        end

      _ServeStream(resolved, stallion.StatusOK, headers)
    end

// Internal result types for ServeFiles._resolve()
class val _ServeInline
  let status: stallion.Status
  let headers: (stallion.Headers val | None)
  let body: ByteSeq

  new val _error(status': stallion.Status, body': ByteSeq) =>
    status = status'
    headers = None
    body = body'

  new val _with_headers(
    status': stallion.Status,
    headers': stallion.Headers val,
    body': ByteSeq)
  =>
    status = status'
    headers = headers'
    body = body'

class val _ServeStream
  let resolved: FilePath
  let status: stallion.Status
  let headers: stallion.Headers val

  new val create(
    resolved': FilePath,
    status': stallion.Status,
    headers': stallion.Headers val)
  =>
    resolved = resolved'
    status = status'
    headers = headers'
