use "files"
use stallion = "stallion"

class val ServeFiles is Handler
  """
  Serve files from a directory on disk.

  Small files (below the chunk threshold) are served as a single
  response with `Content-Length`. Large files are streamed using
  chunked transfer encoding. When the client does not support
  chunked encoding (HTTP/1.0), small files are still served
  normally, but large files are rejected with 505 HTTP Version Not
  Supported to prevent memory exhaustion.

  HEAD requests are optimized: the handler responds with
  `Content-Type` and `Content-Length` headers without reading the
  file, regardless of file size.

  Responses include caching headers:

  - **ETag**: Weak ETag computed from file metadata
    (`W/"<inode>-<size>-<mtime>"`). On Windows, `FileInfo.inode` is
    always 0, reducing collision resistance to size+mtime only.
  - **Last-Modified**: RFC 7231 IMF-fixdate from the file's
    modification time.
  - **Cache-Control**: Configurable via the `cache_control`
    constructor parameter. Defaults to `"public, max-age=3600"`.
    Pass `None` to omit.

  Conditional requests are supported per RFC 7232:

  - `If-None-Match` is checked first (ETag comparison using weak
    matching).
  - `If-Modified-Since` is checked only when `If-None-Match` is
    absent.
  - When either matches, the handler responds with 304 Not Modified
    (cache headers included, no body).

  Custom content types can be added via the `content_types`
  parameter:

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

  actor Main
    new create(env: Env) =>
      let auth = lori.TCPListenAuth(env.root)
      let root =
        FilePath(FileAuth(env.root), "./public")
      hobby.Application
        .>get(
          "/static/*filepath",
          hobby.ServeFiles(root))
        .serve(
          auth,
          stallion.ServerConfig("0.0.0.0", "8080"),
          env.out)
  ```

  Path traversal is prevented by Pony's `FilePath.from()`, which
  rejects any resolved path that is not a child of the base
  directory.

  When a request resolves to a directory, `ServeFiles` looks for an
  `index.html` file inside it. If found, the index file is served
  with the correct `text/html` content type and caching headers. If
  no `index.html` exists, the directory request returns 404.
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
    Create a handler that serves files under `root`.

    `root` must have `FileLookup`, `FileStat`, and `FileRead`
    capabilities. `chunk_threshold` is the file size in kilobytes
    at or above which chunked streaming is used instead of a single
    response. Default: 1024 (1 MB).

    `cache_control` sets the `Cache-Control` header value. Defaults
    to `"public, max-age=3600"` (1 hour). Pass `None` to omit the
    header.

    `content_types` controls the file extension to MIME type
    mapping. Defaults to a `ContentTypes` with 17 common
    extensions. Chain `.add()` calls to add custom mappings.

    If the route uses a wildcard name other than `*filepath`, param
    lookup will fail and the handler will return 500. Always use
    `*filepath`.
    """
    _root = root
    _chunk_threshold = chunk_threshold * 1024
    _cache_control = cache_control
    _content_types = content_types

  fun apply(ctx: Context ref) ? =>
    """
    Serve the file matching the `*filepath` wildcard parameter.

    Resolves the request path against the root directory, applies
    conditional request checks, and responds with the file contents
    (or 304/404/500 as appropriate).
    """
    // Extract the wildcard param -- errors if not named "filepath"
    let filepath = ctx.param("filepath")?

    // Resolve path safely -- errors on traversal attempts
    var resolved =
      try
        FilePath.from(_root, filepath)?
      else
        ctx.respond(
          stallion.StatusNotFound, "Not Found")
        return
      end

    // Stat the file -- errors if file doesn't exist
    var info =
      try
        FileInfo(resolved)?
      else
        ctx.respond(
          stallion.StatusNotFound, "Not Found")
        return
      end

    // Directory -> try serving index.html
    if info.directory then
      resolved =
        try
          FilePath.from(resolved, "index.html")?
        else
          ctx.respond(
            stallion.StatusNotFound, "Not Found")
          return
        end
      info =
        try
          FileInfo(resolved)?
        else
          ctx.respond(
            stallion.StatusNotFound, "Not Found")
          return
        end
    end

    // After index fallback, non-file entries still 404
    if not info.file then
      ctx.respond(
        stallion.StatusNotFound, "Not Found")
      return
    end

    let content_type =
      _content_types(Path.ext(resolved.path))

    // Compute cache identifiers from file metadata
    (let mod_secs, _) = info.modified_time
    let etag = _ETag(info.inode, info.size, mod_secs)
    let last_modified =
      _HTTPDate(mod_secs)

    // Conditional request validation (RFC 7232 S3):
    // If-None-Match takes precedence over If-Modified-Since
    let not_modified =
      match ctx.request.headers.get("if-none-match")
      | let inm: String =>
        _ETag.matches(inm, etag)
      else
        match ctx.request.headers.get(
          "if-modified-since")
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
      ctx.respond_with_headers(
        stallion.StatusNotModified, headers, "")
      return
    end

    // HEAD optimization: respond with headers only, skip file I/O
    // entirely. Content-Length is always set from stat size -- even
    // for files that GET would stream with chunked encoding --
    // since HEAD with Content-Length is more useful to clients
    // (e.g., checking download size) and is explicitly allowed by
    // RFC 7231 S4.3.2.
    if ctx.request.method is stallion.HEAD then
      let headers =
        recover val
          let h = stallion.Headers
            .> set("Content-Type", content_type)
            .> set(
              "Content-Length", info.size.string())
            .> set("ETag", etag)
            .> set("Last-Modified", last_modified)
          match _cache_control
          | let cc: String =>
            h .> set("Cache-Control", cc)
          end
          h
        end
      ctx.respond_with_headers(
        stallion.StatusOK, headers, "")
      return
    end

    if info.size < _chunk_threshold then
      // Small file: read entirely, respond with Content-Length
      let file = File.open(resolved)
      if file.errno() isnt FileOK then error end
      let body = file.read(info.size)
      file.dispose()
      let body_size = body.size()
      let headers =
        recover val
          let h = stallion.Headers
            .> set("Content-Type", content_type)
            .> set(
              "Content-Length", body_size.string())
            .> set("ETag", etag)
            .> set("Last-Modified", last_modified)
          match _cache_control
          | let cc: String =>
            h .> set("Cache-Control", cc)
          end
          h
        end
      ctx.respond_with_headers(
        stallion.StatusOK, headers, consume body)
    else
      // Large file: open before starting stream so failure -> 500
      let file: File iso =
        recover iso
          let f = File.open(resolved)
          if f.errno() isnt FileOK then error end
          f
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
      match ctx.start_streaming(
        stallion.StatusOK, headers)?
      | let sender: StreamSender tag =>
        _FileStreamer(consume file, sender)
      | stallion.ChunkedNotSupported =>
        file.dispose()
        ctx.respond(
          stallion.StatusHTTPVersionNotSupported,
          "HTTP Version Not Supported")
      end
    end
