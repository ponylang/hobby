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

type SignedCookieError is (MalformedSignedValue | InvalidSignature)
  """
  Errors that can occur when verifying a signed cookie value.
  """
