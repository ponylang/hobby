## Add signed cookie support

Hobby now includes `CookieSigningKey` and `SignedCookie` for HMAC-SHA256 cookie signing. The value stays readable, but any tampering invalidates the signature.

```pony
use hobby = "hobby"

// Generate a random 32-byte key at startup
let key = hobby.CookieSigningKey.generate()?

// Sign a value for storage in a cookie
let signed = hobby.SignedCookie.sign(key, "user=alice")

// Verify and extract the original value
match \exhaustive\ hobby.SignedCookie.verify(key, signed)
| let value: String => // "user=alice"
| let err: hobby.SignedCookieError => // tampered or wrong key
end
```

You can also wrap an existing key with `CookieSigningKey(key_bytes)?` — the key must be at least 32 bytes. Verification returns a `SignedCookieError` union (`MalformedSignedValue` or `InvalidSignature`) for exhaustive matching.

## Fix param and wildcard routes failing when a static route shares a long prefix

Routes with `:param` or `*wildcard` segments returned 404 when another static route on the same HTTP method shared a common prefix and was registered first. For example, registering `POST /a/b/c/login` followed by `POST /a/b/c/user/:id/filter` caused the second route to never match.

The router's radix tree splits nodes when routes diverge mid-prefix. The split path was storing the remaining suffix as literal text instead of parsing `:` and `*` markers, so param and wildcard segments after the split point were silently ignored. Route registration order should never affect whether a route matches, and now it doesn't.

