primitive MalformedSignedValue
  """
  The signed cookie value is structurally invalid: it is missing the `.`
  separator between the value and signature, or the signature portion is
  empty or not valid Base64.
  """

  fun string(): String iso^ =>
    "malformed signed value".clone()

primitive InvalidSignature
  """
  The signature did not match the value. The cookie was tampered with or
  signed with a different key.
  """

  fun string(): String iso^ =>
    "invalid signature".clone()

primitive CryptoFailure
  """
  The underlying HMAC operation failed — an extremely rare condition
  caused by a broken or misconfigured OpenSSL installation.
  """

  fun string(): String iso^ =>
    "crypto failure".clone()

type SignedCookieError is
  (MalformedSignedValue | InvalidSignature | CryptoFailure)
  """
  Errors from signing or verifying a signed cookie value.
  """

