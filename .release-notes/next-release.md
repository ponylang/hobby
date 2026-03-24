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

