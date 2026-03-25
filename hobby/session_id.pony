use crypto = "ssl/crypto"

primitive SessionId
  """
  Generates cryptographically random session identifiers.

  Each ID is 32 bytes from the CSPRNG, hex-encoded to a 64-character
  lowercase string. 256 bits of entropy. Hex encoding is used over Base64-URL
  because it is always cookie-safe, unambiguous in logs, and trivially
  validated.

  Errors if the runtime cannot produce secure random bytes — callers must
  treat this as a fatal condition (500 response).
  """

  fun generate(): String val ? =>
    """
    Generate a 64-character hex-encoded session ID from 32 random bytes.

    Errors if the CSPRNG is unavailable.
    """
    let bytes: Array[U8] val = crypto.RandBytes(32)?
    let hex: String iso = recover iso String(64) end
    for b in bytes.values() do
      let hi = (b >> 4) and 0x0F
      let lo = b and 0x0F
      hex.push(_hex_char(hi))
      hex.push(_hex_char(lo))
    end
    consume hex

  fun _hex_char(nibble: U8): U8 =>
    if nibble < 10 then nibble + '0'
    else (nibble - 10) + 'a'
    end
