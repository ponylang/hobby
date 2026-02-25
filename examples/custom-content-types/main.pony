// in your code this `use` statement would be:
// use hobby = "hobby"
use "files"
use hobby = "../../hobby"
use stallion = "stallion"
use lori = "lori"

actor Main
  """
  Custom content type mapping example.

  Starts an HTTP server on 0.0.0.0:8080 that serves files from `public/`
  with custom MIME type mappings for `.webp` and `.avif` image formats.
  These extensions are not in the default set, so without overrides they
  would be served as `application/octet-stream`.

  Usage:
    custom-content-types

  Try it:
    ./build/release/custom-content-types
    curl -I http://localhost:8080/static/photo.webp
    curl -I http://localhost:8080/static/photo.avif
    curl -I http://localhost:8080/static/index.html
  """
  new create(env: Env) =>
    let auth = lori.TCPListenAuth(env.root)
    let root = FilePath(FileAuth(env.root),
      "examples/custom-content-types/public")

    // Add custom content types for .webp and .avif image formats
    let types = hobby.ContentTypes
      .add("webp", "image/webp")
      .add("avif", "image/avif")

    hobby.Application
      .>get("/static/*filepath",
        hobby.ServeFiles(root where content_types = types))
      .serve(auth, stallion.ServerConfig("0.0.0.0", "8080"), env.out)
