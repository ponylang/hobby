// in your code this `use` statement would be:
// use hobby = "hobby"
use hobby = "../../hobby"
use stallion = "stallion"
use lori = "lori"

actor Main
  """
  Signed cookie example.

  Demonstrates signing and verifying cookie values using HMAC-SHA256 to
  prevent tampering. A visit counter cookie is signed on each response and
  verified on each request -- any modification to the value or the signature
  is detected and the count resets.

  Routes:
  - GET /       -> increments and displays a signed visit counter
  - GET /clear  -> clears the visit counter cookie

  Try it:
    curl -c cookies.txt -b cookies.txt http://localhost:8080/
    curl -c cookies.txt -b cookies.txt http://localhost:8080/
    curl -c cookies.txt -b cookies.txt http://localhost:8080/clear
    curl -c cookies.txt -b cookies.txt http://localhost:8080/
  """
  new create(env: Env) =>
    let key =
      try hobby.CookieSigningKey.generate()?
      else env.err.print("Failed to generate signing key"); return
      end
    let auth = lori.TCPListenAuth(env.root)
    match
      hobby.Application
        .>get("/", {(ctx)(key) =>
          let handler = hobby.RequestHandler(consume ctx)
          // Read and verify the signed visit count from the cookie
          let count: U64 =
            match handler.request().cookies.get("visits")
            | let raw: String =>
              match \exhaustive\ hobby.SignedCookie.verify(key, raw)
              | let value: String =>
                try value.u64()? else 0 end
              | let _: hobby.SignedCookieError => 0
              end
            else
              0
            end
          let new_count: String val = (count + 1).string()
          let signed = hobby.SignedCookie.sign(key, new_count)
          // Build response headers with the signed cookie.
          // Secure=false for localhost testing; use the default (true) in
          // production.
          let headers: stallion.Headers val =
            recover val
              let h = stallion.Headers
              match stallion.SetCookieBuilder("visits", signed)
                .with_path("/")
                .with_secure(false)
                .build()
              | let sc: stallion.SetCookie val =>
                h.add("Set-Cookie", sc.header_value())
              end
              h
            end
          handler.respond_with_headers(stallion.StatusOK, headers,
            "Visit #" + new_count)
        } val)
        .>get("/clear", {(ctx) =>
          let handler = hobby.RequestHandler(consume ctx)
          // Clear the cookie by setting Max-Age=0
          let headers: stallion.Headers val =
            recover val
              let h = stallion.Headers
              match stallion.SetCookieBuilder("visits", "")
                .with_path("/")
                .with_max_age(0)
                .with_secure(false)
                .build()
              | let sc: stallion.SetCookie val =>
                h.add("Set-Cookie", sc.header_value())
              end
              h
            end
          handler.respond_with_headers(stallion.StatusOK, headers,
            "Visit counter cleared.")
        } val)
        .serve(auth, stallion.ServerConfig("0.0.0.0", "8080"), env.out)
    | let err: hobby.ConfigError =>
      env.err.print(err.message)
    end
