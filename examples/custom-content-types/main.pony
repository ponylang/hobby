// in your code this `use` statement would be:
// use hobby = "hobby"
use "files"
use hobby = "../../hobby"
use stallion = "stallion"
use lori = "lori"

actor Main is hobby.ServerNotify
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

  let _env: Env

  new create(env: Env) =>
    _env = env
    let auth = lori.TCPListenAuth(env.root)
    let root =
      FilePath(
        FileAuth(env.root),
        "examples/custom-content-types/public")

    // Add custom content types for .webp and .avif image formats
    let types = hobby.ContentTypes
      .add("webp", "image/webp")
      .add("avif", "image/avif")

    let app = hobby.Application
      .> get(
        "/static/*filepath",
        hobby.ServeFiles(root where content_types = types))

    match \exhaustive\ app.build()
    | let built: hobby.BuiltApplication =>
      hobby.Server(
        auth, built, this
        where host = "0.0.0.0", port = "8080")
    | let err: hobby.ConfigError =>
      env.err.print(err.message)
    end

  be listening(
    server: hobby.Server,
    host: String,
    service: String)
  =>
    _env.out.print(
      "Listening on " + host + ":" + service)

  be listen_failed(
    server: hobby.Server,
    reason: String)
  =>
    _env.err.print(reason)
