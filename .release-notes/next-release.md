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

Content-Type is detected from file extensions. Path traversal is prevented by Pony's `FilePath.from()` capability system. HTTP/1.0 clients requesting files above the chunk threshold receive 505 HTTP Version Not Supported rather than having the entire file loaded into memory. Directory requests return 404 — there is no automatic index file lookup (e.g., requesting `/static/` does not serve `/static/index.html`).

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

