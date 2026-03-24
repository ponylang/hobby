use crypto = "ssl/crypto"
use "encode/base64"

primitive SignedCookie
  """
  Signs and verifies cookie values using HMAC-SHA256.

  The signed format is `value.base64url(hmac)`. The value is readable
  (not encrypted); the signature proves integrity.
  """

  fun sign(key: CookieSigningKey, value: String val): String val =>
    """
    Sign `value` and return the signed string `value.signature`.
    """
    let hmac: Array[U8] val = crypto.HmacSha256(key._bytes(), value)
    let sig: String val =
      Base64.encode_url[String iso](hmac where pad = true)
    recover val
      String(value.size() + 1 + sig.size())
        .> append(value)
        .> push('.')
        .> append(sig)
    end

  fun verify(
    key: CookieSigningKey,
    signed_value: String val)
    : (String val | SignedCookieError)
  =>
    """
    Verify the signature on `signed_value`. Returns the original value
    on success, or a `SignedCookieError` describing the failure.
    """
    let pos: ISize =
      try
        signed_value.rfind(".")?
      else
        return MalformedSignedValue
      end

    let value: String val = signed_value.trim(0, pos.usize())
    let sig_b64: String val = signed_value.trim(pos.usize() + 1)

    if sig_b64.size() == 0 then
      return MalformedSignedValue
    end

    let decoded: Array[U8] val =
      try
        recover val Base64.decode_url[Array[U8] iso](sig_b64)? end
      else
        return MalformedSignedValue
      end

    let expected: Array[U8] val = crypto.HmacSha256(key._bytes(), value)

    if crypto.ConstantTimeCompare(expected, decoded) then
      value
    else
      InvalidSignature
    end
