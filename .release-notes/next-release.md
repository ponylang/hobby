## Add cookie support

Stallion 0.5.0 brings cookie parsing and serialization, and hobby users get it for free through `ctx.request`. Cookies from the `Cookie` header are automatically parsed and available on the request object:

```pony
fun apply(ctx: hobby.Context ref) ? =>
  match ctx.request.cookies.get("session")
  | let token: String val =>
    // use the session token
  end
```

To set cookies in responses, use `stallion.SetCookieBuilder` to construct `Set-Cookie` headers. The builder defaults to `Secure`, `HttpOnly`, and `SameSite=Lax` so you have to opt out of safety rather than opt in:

```pony
fun apply(ctx: hobby.Context ref) ? =>
  match stallion.SetCookieBuilder("session", token)
    .with_path("/")
    .with_max_age(3600)
    .build()
  | let sc: stallion.SetCookie val =>
    let headers = stallion.Headers
      .add("Set-Cookie", sc.header_value())
      .add("Content-Length", "2")
    ctx.respond_with_headers(stallion.StatusOK, headers, "OK")
  | let err: stallion.SetCookieBuildError =>
    ctx.respond(stallion.StatusInternalServerError, "Cookie build failed")
  end
```

## Add content negotiation

Also from stallion 0.5.0, handlers can now negotiate response content type based on the client's `Accept` header. This is useful for endpoints that need to serve multiple formats:

```pony
fun apply(ctx: hobby.Context ref) ? =>
  let supported = [as stallion.MediaType val:
    stallion.MediaType("application", "json")
    stallion.MediaType("text", "plain")
  ]
  match stallion.ContentNegotiation.from_request(ctx.request, supported)
  | let mt: stallion.MediaType val =>
    if mt.string() == "application/json" then
      ctx.respond(stallion.StatusOK, "{\"hello\": \"world\"}")
    else
      ctx.respond(stallion.StatusOK, "hello world")
    end
  | stallion.NoAcceptableType =>
    ctx.respond(stallion.StatusNotAcceptable, "")
  end
```

The algorithm follows RFC 7231 precedence rules. Most endpoints serve a single content type and don't need this, but it's there when you do.

## Change `Headers.values()` to yield `Header val`

Stallion 0.5.0 changed `Headers.values()` to yield `Header val` objects instead of `(String, String)` tuples. If your handlers or middleware iterate request headers directly, you'll need to update the iteration pattern.

Before:

```pony
for (name, value) in ctx.request.headers.values() do
  env.out.print(name + ": " + value)
end
```

After:

```pony
for hdr in ctx.request.headers.values() do
  env.out.print(hdr.name + ": " + hdr.value)
end
```
