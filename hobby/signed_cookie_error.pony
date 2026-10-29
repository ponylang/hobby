primitive MalformedSignedValue
  """
  The signed cookie value is structurally invalid: it is missing the `.`
  separator between the value and signature, or the signature portion is
  empty or not valid Base64.
  """

  fun string(): String =>
    "malformed signed value"

primitive InvalidSignature
  """
  The signature did not match the value. The cookie was tampered with or
  signed with a different key.
  """

  fun string(): String =>
    "invalid signature"

primitive CryptoFailure
  """
  The underlying HMAC operation failed — an extremely rare condition
  caused by a broken or misconfigured OpenSSL installation.
  """

  fun string(): String =>
    "crypto failure"

type SignedCookieError is
  (MalformedSignedValue | InvalidSignature | CryptoFailure)
  """
  Errors from signing or verifying a signed cookie value.
  """

