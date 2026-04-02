use crypto = "ssl/crypto"

class val CookieSigningKey
  """

  An HMAC-SHA256 signing key for use with `SignedCookie`.

  Keys must be at least 32 bytes. Use `generate` to create a random key
  or `create` to wrap an existing one.
  """


  let _key: Array[U8] val

  new val create(key: Array[U8] val) ? =>
    """

    Wrap an existing key. Errors if `key` is shorter than 32 bytes.
    """

    if key.size() < 32 then error end
    _key = key

  new val generate() ? =>
    """

    Generate a 32-byte key from a cryptographically secure random source.
    Errors if the runtime cannot produce secure random bytes.
    """

    _key = crypto.RandBytes(32)?

  fun _bytes(): Array[U8] val =>
    """

    Return the raw key bytes.
    """

    _key
