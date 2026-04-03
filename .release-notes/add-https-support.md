## Add HTTPS support via serve_ssl()

Hobby can now serve HTTPS. Use `serve_ssl()` instead of `serve()` and pass an `SSLContext val` configured with your certificate and key:

```pony
use "files"
use hobby = "hobby"
use stallion = "stallion"
use lori = "lori"
use ssl_net = "ssl/net"

actor Main
  new create(env: Env) =>
    let auth = lori.TCPListenAuth(env.root)
    let file_auth = FileAuth(env.root)
    let sslctx =
      try
        recover val
          ssl_net.SSLContext
            .> set_authority(FilePath(file_auth, "cert.pem"))?
            .> set_cert(
              FilePath(file_auth, "cert.pem"),
              FilePath(file_auth, "key.pem"))?
            .> set_client_verify(false)
            .> set_server_verify(false)
        end
      else
        env.err.print("Unable to set up SSL context")
        return
      end

    match
      hobby.Application
        .> get("/", {(ctx) =>
          hobby.RequestHandler(consume ctx)
            .respond(stallion.StatusOK, "Hello over HTTPS!")
        } val)
        .serve_ssl(auth, stallion.ServerConfig("0.0.0.0", "8443"),
          env.out, sslctx)
    | let err: hobby.ConfigError =>
      env.err.print(err.message)
    end
```

`serve_ssl()` follows the same pattern as Stallion's `HTTPServer.ssl()` — a separate method where the SSL context is required, not optional. You can't accidentally start HTTPS without a context or start HTTP when you meant HTTPS.

If the SSL context is misconfigured (no certificate set, wrong key), `serve_ssl()` still returns `Serving` but every connection fails at TLS handshake time. These failures are now logged as "Hobby: connection failed (SSL handshake)" to the `OutStream` you pass to `serve_ssl()`, so misconfigured deployments are visible to the operator instead of silently dropping connections.
