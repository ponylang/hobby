## Add built-in static file serving

Serve files from a directory using the new `ServeFiles` handler:

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

Small files are served as a single response with `Content-Length`. Large files (at or above the chunk threshold) are streamed using chunked transfer encoding with scheduler-fair 64 KB reads. The `chunk_threshold` parameter controls the cutoff in kilobytes (default 1024, i.e. 1 MB):

```pony
// Stream files at or above 256 KB instead of the default 1 MB
hobby.ServeFiles(root where chunk_threshold = 256)
```

Content-Type is detected from file extensions. Path traversal is prevented by Pony's `FilePath.from()` capability system. HTTP/1.0 clients requesting files above the chunk threshold receive 505 HTTP Version Not Supported rather than having the entire file loaded into memory. When a request resolves to a directory, `ServeFiles` automatically serves `index.html` from that directory if it exists; otherwise the request returns 404.

## Add automatic HEAD request support

HEAD requests are handled automatically per RFC 7231 §4.3.2. The framework suppresses response bodies while preserving headers (including `Content-Length`). No changes are needed in handlers for non-streaming responses.

When no explicit HEAD route is registered, HEAD requests automatically fall back to the matching GET handler. Explicit HEAD routes (registered via `Application.head()`) take precedence.

For streaming handlers, `start_streaming()` returns `BodyNotNeeded` instead of starting a stream:

```pony
match ctx.start_streaming(stallion.StatusOK)?
| let sender: hobby.StreamSender tag =>
  MyProducer(sender)
| stallion.ChunkedNotSupported =>
  ctx.respond(stallion.StatusOK, "Upgrade to HTTP/1.1.")
| hobby.BodyNotNeeded => None
end
```

Existing handlers that don't match on `BodyNotNeeded` work correctly — in a statement-position match, unmatched cases silently fall through. Only handlers that assign the match result need updating.

`ServeFiles` is optimized for HEAD: it responds with `Content-Type` and `Content-Length` headers (from file stat) without reading the file, regardless of file size.

## Change `start_streaming()` return type

`Context.start_streaming()` now returns `(StreamSender tag | ChunkedNotSupported | BodyNotNeeded)` instead of `(StreamSender tag | ChunkedNotSupported)`.

Before:

```pony
match ctx.start_streaming(stallion.StatusOK)?
| let sender: hobby.StreamSender tag =>
  MyProducer(sender)
| stallion.ChunkedNotSupported =>
  ctx.respond(stallion.StatusOK, "Fallback response.")
end
```

After:

```pony
match ctx.start_streaming(stallion.StatusOK)?
| let sender: hobby.StreamSender tag =>
  MyProducer(sender)
| stallion.ChunkedNotSupported =>
  ctx.respond(stallion.StatusOK, "Fallback response.")
| hobby.BodyNotNeeded => None
end
```

## Add caching headers for ServeFiles

`ServeFiles` now includes caching headers on all responses:

- **ETag**: Weak ETag computed from file metadata (`W/"<inode>-<size>-<mtime>"`).
- **Last-Modified**: RFC 7231 HTTP-date from the file's modification time.
- **Cache-Control**: Defaults to `"public, max-age=3600"`. Customizable via the new `cache_control` constructor parameter, or pass `None` to omit.

Conditional requests are supported per RFC 7232 — clients can send `If-None-Match` or `If-Modified-Since` headers to receive 304 Not Modified when the file hasn't changed, avoiding re-downloading unchanged files.

```pony
// Default: 1-hour public caching
hobby.ServeFiles(root)

// Custom cache policy
hobby.ServeFiles(root where cache_control = "private, max-age=600")

// No Cache-Control header
hobby.ServeFiles(root where cache_control = None)
```

## Add automatic index file serving for directories

When a request to `ServeFiles` resolves to a directory, it now automatically serves `index.html` from that directory if the file exists. If no `index.html` is present, the request returns 404 as before.

```pony
// Given public/docs/index.html exists:
// GET /static/docs/ → serves public/docs/index.html with text/html Content-Type
// GET /static/docs  → same (trailing slash normalization)
```

The index file gets the same treatment as any other served file — correct Content-Type (`text/html`), caching headers (ETag, Last-Modified, Cache-Control), conditional request support, and HEAD optimization.
