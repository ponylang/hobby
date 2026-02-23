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

Small files are served as a single response with `Content-Length`. Large files (at or above the configurable chunk threshold, default 1 MB) are streamed using chunked transfer encoding with scheduler-fair 64 KB reads. Content-Type is detected from file extensions. Path traversal is prevented by Pony's `FilePath.from()` capability system. HTTP/1.0 clients requesting files above the chunk threshold receive 505 HTTP Version Not Supported rather than having the entire file loaded into memory.
