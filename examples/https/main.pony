// in your code this `use` statement would be:
// use hobby = "hobby"
use hobby = "../../hobby"
use "files"
use stallion = "stallion"
use lori = "lori"
use ssl_net = "ssl/net"

actor Main
  """
  HTTPS example.

  Starts an HTTPS server on 0.0.0.0:8443 using a self-signed
  certificate from the project's assets/ directory.

  Try it:
    curl -k https://localhost:8443/
    curl -k https://localhost:8443/greet/World
  """

  new create(env: Env) =>
    let auth = lori.TCPListenAuth(env.root)
    let file_auth = FileAuth(env.root)
    let sslctx =
      try
        recover val
          ssl_net.SSLContext
            .> set_authority(
              FilePath(file_auth, "assets/cert.pem"))?
            .> set_cert(
              FilePath(file_auth, "assets/cert.pem"),
              FilePath(file_auth, "assets/key.pem"))?
            .> set_client_verify(false)
            .> set_server_verify(false)
        end
      else
        env.err.print("Unable to set up SSL context")
        return
      end

    match
      hobby.Application
        .> get(
          "/",
          {(ctx) =>
            hobby.RequestHandler(consume ctx)
              .respond(
                stallion.StatusOK,
                "Hello over HTTPS!")
          } val)
        .> get(
          "/greet/:name",
          {(ctx) =>
            let handler = hobby.RequestHandler(consume ctx)
            try
              let name = handler.param("name")?
              handler.respond(
                stallion.StatusOK,
                "Hello, " + name + "!")
            else
              handler.respond(
                stallion.StatusBadRequest, "Bad Request")
            end
          } val)
        .serve_ssl(
          auth,
          stallion.ServerConfig("0.0.0.0", "8443"),
          env.out,
          sslctx)
    | let err: hobby.ConfigError =>
      env.err.print(err.message)
    end
