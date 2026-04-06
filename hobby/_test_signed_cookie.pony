use "pony_test"
use "pony_check"
use crypto = "ssl/crypto"

primitive \nodoc\ _TestSignedCookieList
  fun tests(test: PonyTest) =>
    test(_TestSignedCookieRoundTrip)
    test(_TestSignedCookieTamperedValue)
    test(_TestSignedCookieTamperedSig)
    test(_TestSignedCookieNoSeparator)
    test(_TestSignedCookieEmptySig)
    test(_TestSignedCookieWrongKey)
    test(_TestSignedCookieValueWithDots)
    test(_TestSignedCookieEmptyValue)
    test(_TestSignedCookieInvalidBase64)
    test(_TestSignedCookieKeyBoundary)
    test(_TestSignedCookieRfc4231Vector)
    test(_TestSignedCookieCrossLanguageVector)
    test(Property1UnitTest[String](_PropSignedCookieRoundTrip))
    test(Property1UnitTest[String](_PropSignedCookieDeterministic))
    test(Property1UnitTest[
      (String, USize)](_PropSignedCookieTamperDetection))
    test(Property1UnitTest[String](_PropSignedCookieKeyIndependence))
    test(Property1UnitTest[String](_PropSignedCookieCookieOctetValidity))
    test(Property1UnitTest[String](_PropSignedCookieSignatureLength))

class \nodoc\ iso _TestSignedCookieRoundTrip is UnitTest
  fun name(): String => "SignedCookie/round-trip"

  fun apply(h: TestHelper) ? =>
    let key = CookieSigningKey.generate()?
    let value = "user=alice"
    let signed = SignedCookie.sign(key, value)
    match \exhaustive\ SignedCookie.verify(key, signed)
    | let v: String => h.assert_eq[String](value, v)
    | let e: SignedCookieError => h.fail(e.string())
    end

class \nodoc\ iso _TestSignedCookieTamperedValue is UnitTest
  fun name(): String => "SignedCookie/tampered-value"

  fun apply(h: TestHelper) ? =>
    let key = CookieSigningKey.generate()?
    let signed = SignedCookie.sign(key, "user=alice")
    // Replace "alice" with "mallory"
    let sig_part = signed.trim(signed.rfind(".")?.usize())
    let tampered =
      recover val
        String
          .> append("user=mallory")
          .> append(sig_part)
      end
    match \exhaustive\ SignedCookie.verify(key, tampered)
    | let _: String => h.fail("accepted tampered value")
    | InvalidSignature => None
    | MalformedSignedValue => h.fail("wrong error type")
    end

class \nodoc\ iso _TestSignedCookieTamperedSig is UnitTest
  fun name(): String => "SignedCookie/tampered-signature"

  fun apply(h: TestHelper) ? =>
    let key = CookieSigningKey.generate()?
    let signed = SignedCookie.sign(key, "user=alice")
    let pos = signed.rfind(".")?.usize()
    let value = signed.trim(0, pos)
    // Replace the signature with a different valid Base64 string
    let tampered =
      recover val
        String
          .> append(value)
          .> push('.')
          .> append("AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=")
      end
    match \exhaustive\ SignedCookie.verify(key, tampered)
    | let _: String => h.fail("accepted tampered signature")
    | InvalidSignature => None
    | MalformedSignedValue => h.fail("wrong error type")
    end

class \nodoc\ iso _TestSignedCookieNoSeparator is UnitTest
  fun name(): String => "SignedCookie/no-separator"

  fun apply(h: TestHelper) =>
    let key =
      try CookieSigningKey.generate()?
      else h.fail("key generation failed"); return
      end
    match \exhaustive\ SignedCookie.verify(key, "noseparatorhere")
    | let _: String => h.fail("accepted value without separator")
    | MalformedSignedValue => None
    | InvalidSignature => h.fail("wrong error type")
    end

class \nodoc\ iso _TestSignedCookieEmptySig is UnitTest
  fun name(): String => "SignedCookie/empty-signature"

  fun apply(h: TestHelper) =>
    let key =
      try CookieSigningKey.generate()?
      else h.fail("key generation failed"); return
      end
    match \exhaustive\ SignedCookie.verify(key, "value.")
    | let _: String => h.fail("accepted empty signature")
    | MalformedSignedValue => None
    | InvalidSignature => h.fail("wrong error type")
    end

class \nodoc\ iso _TestSignedCookieWrongKey is UnitTest
  fun name(): String => "SignedCookie/wrong-key"

  fun apply(h: TestHelper) =>
    (let key1, let key2) =
      try
        (CookieSigningKey.generate()?, CookieSigningKey.generate()?)
      else
        h.fail("key generation failed"); return
      end
    let signed = SignedCookie.sign(key1, "secret")
    match \exhaustive\ SignedCookie.verify(key2, signed)
    | let _: String => h.fail("accepted wrong key")
    | InvalidSignature => None
    | MalformedSignedValue => h.fail("wrong error type")
    end

class \nodoc\ iso _TestSignedCookieValueWithDots is UnitTest
  fun name(): String => "SignedCookie/value-with-dots"

  fun apply(h: TestHelper) =>
    let key =
      try CookieSigningKey.generate()?
      else h.fail("key generation failed"); return
      end
    let value = "a.b.c.d"
    let signed = SignedCookie.sign(key, value)
    match \exhaustive\ SignedCookie.verify(key, signed)
    | let v: String => h.assert_eq[String](value, v)
    | let e: SignedCookieError => h.fail(e.string())
    end

class \nodoc\ iso _TestSignedCookieEmptyValue is UnitTest
  fun name(): String => "SignedCookie/empty-value"

  fun apply(h: TestHelper) =>
    let key =
      try CookieSigningKey.generate()?
      else h.fail("key generation failed"); return
      end
    let value = ""
    let signed = SignedCookie.sign(key, value)
    match \exhaustive\ SignedCookie.verify(key, signed)
    | let v: String => h.assert_eq[String](value, v)
    | let e: SignedCookieError => h.fail(e.string())
    end

class \nodoc\ iso _TestSignedCookieInvalidBase64 is UnitTest
  fun name(): String => "SignedCookie/invalid-base64"

  fun apply(h: TestHelper) =>
    let key =
      try CookieSigningKey.generate()?
      else h.fail("key generation failed"); return
      end
    match \exhaustive\ SignedCookie.verify(key, "value.@@@not-base64!!!")
    | let _: String => h.fail("accepted invalid base64")
    | MalformedSignedValue => None
    | InvalidSignature => h.fail("wrong error type")
    end

class \nodoc\ iso _TestSignedCookieKeyBoundary is UnitTest
  """
  The minimum key length is 32 bytes. A 31-byte key must be rejected;
  a 32-byte key must be accepted.
  """

  fun name(): String => "SignedCookie/key-boundary"

  fun apply(h: TestHelper) =>
    let too_short: Array[U8] val =
      recover val Array[U8].init(0xAA, 31) end
    try
      CookieSigningKey(too_short)?
      h.fail("accepted 31-byte key")
    end

    let just_right: Array[U8] val =
      recover val Array[U8].init(0xAA, 32) end
    try
      CookieSigningKey(just_right)?
    else
      h.fail("rejected 32-byte key")
    end

class \nodoc\ iso _TestSignedCookieRfc4231Vector is UnitTest
  """
  RFC 4231 Test Case 2: HMAC-SHA256 with "Jefe" key and "what do ya want
  for nothing?" data. Verifies our HMAC matches the known digest.
  """

  fun name(): String => "SignedCookie/rfc-4231-vector"

  fun apply(h: TestHelper) =>
    // RFC 4231 Test Case 2 key: "Jefe" (4 bytes) — too short for
    // CookieSigningKey, so test the HMAC primitive directly.
    let key: Array[U8] val = [as U8: 0x4a; 0x65; 0x66; 0x65]
    let data = "what do ya want for nothing?"
    let expected: Array[U8] val =
      [ as U8:
        0x5b; 0xdc; 0xc1; 0x46; 0xbf; 0x60; 0x75; 0x4e
        0x6a; 0x04; 0x24; 0x26; 0x08; 0x95; 0x75; 0xc7
        0x5a; 0x00; 0x3f; 0x08; 0x9d; 0x27; 0x39; 0x83
        0x9d; 0xec; 0x58; 0xb9; 0x64; 0xec; 0x38; 0x43
      ]
    let actual = crypto.HmacSha256(key, data)
    h.assert_eq[USize](32, actual.size())
    h.assert_true(
      crypto.ConstantTimeCompare(expected, actual),
      "HMAC did not match RFC 4231 test vector")

class \nodoc\ iso _TestSignedCookieCrossLanguageVector is UnitTest
  """
  Cross-language test vector: a known key, value, and expected signed
  output verified against `openssl dgst -sha256 -hmac`.

  Reproduce with:
  ```
  printf 'hello' \
    | openssl dgst -sha256 \
        -mac HMAC \
        -macopt hexkey:$(python3 -c "print('ab'*32)") \
        -binary \
    | base64 -w0 \
    | tr '+/' '-_'
  ```

  Key: 32 bytes of 0xAB
  Value: "hello"
  Expected signed output: "hello.7GT0SrIsQCeVHsMIKW5wg_p2huSb8nTFCUeO-QsJ_Ak=
  """

  fun name(): String => "SignedCookie/cross-language-vector"

  fun apply(h: TestHelper) ? =>
    let key_bytes: Array[U8] val =
      recover val Array[U8].init(0xAB, 32) end
    let key = CookieSigningKey(key_bytes)?

    let expected = "hello.7GT0SrIsQCeVHsMIKW5wg_p2huSb8nTFCUeO-QsJ_Ak="
    let signed = SignedCookie.sign(key, "hello")
    h.assert_eq[String](expected, signed)

    match \exhaustive\ SignedCookie.verify(key, signed)
    | let v: String => h.assert_eq[String]("hello", v)
    | let e: SignedCookieError => h.fail(e.string())
    end

class \nodoc\ iso _PropSignedCookieRoundTrip is Property1[String]
  """
  For any printable ASCII value, sign then verify returns the original.
  """

  fun name(): String => "SignedCookie/prop-round-trip"

  fun gen(): Generator[String] =>
    Generators.ascii_printable(0, 200)

  fun property(sample: String, h: PropertyHelper) =>
    let key =
      try CookieSigningKey.generate()?
      else h.fail("key generation failed"); return
      end
    let signed = SignedCookie.sign(key, sample)
    match \exhaustive\ SignedCookie.verify(key, signed)
    | let v: String => h.assert_eq[String](sample, v)
    | let e: SignedCookieError => h.fail(e.string())
    end

class \nodoc\ iso _PropSignedCookieDeterministic is Property1[String]
  """
  Signing the same value with the same key always produces the same output.
  """

  fun name(): String => "SignedCookie/prop-deterministic"

  fun gen(): Generator[String] =>
    Generators.ascii_printable(0, 200)

  fun property(sample: String, h: PropertyHelper) =>
    let key =
      try CookieSigningKey.generate()?
      else h.fail("key generation failed"); return
      end
    let a = SignedCookie.sign(key, sample)
    let b = SignedCookie.sign(key, sample)
    h.assert_eq[String](a, b)

class \nodoc\ iso _PropSignedCookieTamperDetection is
  Property1[(String, USize)]
  """
  Flipping any byte in a signed value causes verification to fail.
  """

  fun name(): String => "SignedCookie/prop-tamper-detection"

  fun gen(): Generator[(String, USize)] =>
    Generators.map2[String, USize, (String, USize)](
      Generators.ascii_printable(1, 100),
      Generators.usize(0, 200),
      {(s, i) => (s, i) })

  fun property(sample: (String, USize), h: PropertyHelper) =>
    (let value, let flip_hint) = sample
    let key =
      try CookieSigningKey.generate()?
      else h.fail("key generation failed"); return
      end
    let signed = SignedCookie.sign(key, value)

    if signed.size() == 0 then return end
    let flip_pos = flip_hint % signed.size()

    // Build a tampered copy with one byte flipped
    let tampered =
      recover val
        let buf = signed.clone()
        try
          let original = buf(flip_pos)?
          // XOR with a non-zero value to guarantee a change
          buf(flip_pos)? = original xor 0xFF
        else
          return
        end
        consume buf
      end

    match \exhaustive\ SignedCookie.verify(key, tampered)
    | let _: String => h.fail("accepted tampered value")
    | let _: SignedCookieError => None
    end

class \nodoc\ iso _PropSignedCookieKeyIndependence is Property1[String]
  """
  A value signed with one key does not verify with a different key.
  """

  fun name(): String => "SignedCookie/prop-key-independence"

  fun gen(): Generator[String] =>
    Generators.ascii_printable(0, 200)

  fun property(sample: String, h: PropertyHelper) =>
    (let key1, let key2) =
      try
        (CookieSigningKey.generate()?, CookieSigningKey.generate()?)
      else
        h.fail("key generation failed"); return
      end
    let signed = SignedCookie.sign(key1, sample)
    match \exhaustive\ SignedCookie.verify(key2, signed)
    | let _: String => h.fail("different key accepted")
    | let _: SignedCookieError => None
    end

class \nodoc\ iso _PropSignedCookieCookieOctetValidity is Property1[String]
  """
  The separator and signature portion of a signed cookie contain only
  valid cookie-octet bytes (RFC 6265 section 4.1.1): US-ASCII excluding
  control characters, whitespace, double quote, comma, semicolon, and
  backslash. The value portion is the caller's responsibility.
  """

  fun name(): String => "SignedCookie/prop-cookie-octet-validity"

  fun gen(): Generator[String] =>
    Generators.ascii_printable(0, 200)

  fun property(sample: String, h: PropertyHelper) =>
    let key =
      try CookieSigningKey.generate()?
      else h.fail("key generation failed"); return
      end
    let signed = SignedCookie.sign(key, sample)
    // Check only the dot separator and signature, not the user-supplied value
    let pos =
      try signed.rfind(".")?.usize()
      else h.fail("no separator in signed output"); return
      end
    let suffix = signed.trim(pos)
    for byte in suffix.values() do
      // cookie-octet: 0x21-0x7E minus 0x22 ("), 0x2C (,), 0x3B (;), 0x5C (\)
      if byte <= 0x20 then
        h.fail("byte <= 0x20: " + byte.string()); return
      elseif byte > 0x7E then
        h.fail("byte > 0x7E: " + byte.string()); return
      elseif byte == 0x22 then
        h.fail("contains double quote"); return
      elseif byte == 0x2C then
        h.fail("contains comma"); return
      elseif byte == 0x3B then
        h.fail("contains semicolon"); return
      elseif byte == 0x5C then
        h.fail("contains backslash"); return
      end
    end

class \nodoc\ iso _PropSignedCookieSignatureLength is Property1[String]
  """
  The signature portion (after the last `.`) is always 44 characters —
  the Base64-URL encoding of a 32-byte HMAC with padding.
  """

  fun name(): String => "SignedCookie/prop-signature-length"

  fun gen(): Generator[String] =>
    Generators.ascii_printable(0, 200)

  fun property(sample: String, h: PropertyHelper) =>
    let key =
      try CookieSigningKey.generate()?
      else h.fail("key generation failed"); return
      end
    let signed = SignedCookie.sign(key, sample)
    let pos =
      try signed.rfind(".")?.usize()
      else h.fail("no separator in signed output"); return
      end
    let sig = signed.trim(pos + 1)
    h.assert_eq[USize](44, sig.size())
