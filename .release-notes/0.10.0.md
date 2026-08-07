## Fix streaming responses stalling under several conditions

A streaming response could stall and never complete. The callback that tracks when a chunk's bytes reach the operating system fired once per write-queue drain instead of once per chunk, and when the connection closed, pending callbacks were discarded entirely. A handler driving the next chunk from the previous one's completion would stop sending when a callback it waited on never arrived.

Each chunk now gets its own callback, in send order, and callbacks for bytes already delivered to the operating system are no longer discarded when the connection closes.

## Fix a hang when a handler closes the server from a request callback

Calling `server.dispose()` from inside a handler could leave a stray read outstanding on the closed socket. Under connection churn that read could block a scheduler thread and prevent the program from exiting.

## Fix a connection wedging under sustained write backpressure

A connection could permanently stop making progress under sustained write backpressure while the client was still sending. The connection did not recover on its own, staying wedged until something closed it. Most likely on a multi-threaded runtime.

## Fix HTTPS connections receiving more requests after throttling

On an HTTPS connection, `throttled()` did not stop request delivery. Data already decrypted from the same TLS record was parsed, so a handler that had just received `throttled()` could still be handed more requests. Plaintext connections were not affected. HTTPS connections now stop delivering requests as soon as throttling is applied.

## Fix a possible write hang under load

Sending response data could hang the program when the send buffer filled on a descriptor that the operating system had reused for a blocking socket. Fixed on Linux, FreeBSD, OpenBSD, and DragonFly.

## Fix several SSL connection bugs

Fixed multiple bugs affecting SSL connections: handshake failures being reported as authentication failures, data being silently dropped on large writes and when encryption fails, and one connection's SSL failure closing a different connection.

## Send TLS close_notify on graceful close

Closing a TLS connection now sends a `close_notify` alert before the TCP shutdown. Without it, the peer could not distinguish a clean close from a truncated stream.

## SignedCookie.sign() returns a result instead of a plain String

`SignedCookie.sign()` previously returned `String val`. It now returns `(String val | SignedCookieError)` and can return `CryptoFailure` when the HMAC operation fails. The old return type masked a silent failure: the HMAC could produce an all-zero code when the operation failed, yielding a signed cookie with an invalid signature.

```pony
// Before
let signed: String val = SignedCookie.sign(key, value)

// After
match SignedCookie.sign(key, value)
| let signed: String => // use signed
| let err: SignedCookieError => // handle failure
end
```

`CryptoFailure` is also a new member of `SignedCookieError`, so exhaustive matches on `SignedCookie.verify()` results that list error primitives individually need the new arm:

```pony
// Before
match \exhaustive\ SignedCookie.verify(key, raw)
| let v: String => v
| InvalidSignature => "bad"
| MalformedSignedValue => "bad"
end

// After
match \exhaustive\ SignedCookie.verify(key, raw)
| let v: String => v
| InvalidSignature => "bad"
| MalformedSignedValue => "bad"
| CryptoFailure => "bad"
end
```

Matches that use `let _: SignedCookieError` are unaffected.

## Require ponyc 0.67.0 or later

The previous minimum was 0.64.0. The write-hang fix depends on a socket call added in ponyc 0.67.0.

## Move to ssl 4.0.0

Hobby now uses ssl 4.0.0, where it used 2.0.1. Hobby's own SSL API is unchanged: pass an `SSLContext val` to `Server.ssl()` exactly as before.

Code that uses `ssl/net` or `ssl/crypto` directly can break. If your application does not declare ssl in its own `corral.json`, it gets 4.0.0 through hobby.

The most common breaks: the twelve protocol-version primitives spell their acronyms in full (`Tls1u2Version` is now `TLS1u2Version`), `SSLContext.alpn_set_resolver` takes a `val` resolver instead of `box`, `SSLState` has a new `SSLDisposed` member that breaks exhaustive matches, and `Digest`/`HmacSha256` now raise on failure. See the ssl 3.0.0 and 4.0.0 changelogs for the full list.
