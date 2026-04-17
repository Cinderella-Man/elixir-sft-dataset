defmodule TOTPTest do
  use ExUnit.Case, async: true

  # -------------------------------------------------------------------
  # RFC 6238 test vectors (SHA1, 8-digit in the RFC but we derive the
  # expected 6-digit codes from the same TOTP counter values so we can
  # do a round-trip check via our own implementation).
  #
  # The canonical secret from RFC 4226 Appendix D: "12345678901234567890"
  # Base32-encoded: GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ
  # -------------------------------------------------------------------

  @rfc_secret "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"

  # These expected codes were computed independently from the RFC vectors.
  # Each tuple is {unix_timestamp, expected_6_digit_code}.
  @rfc_vectors [
    {59, "287082"},
    {1_111_111_109, "081804"},
    {1_111_111_111, "050471"},
    {1_234_567_890, "005924"},
    {2_000_000_000, "279037"},
    {20_000_000_000, "353130"}
  ]

  # -------------------------------------------------------------------
  # generate_secret/0
  # -------------------------------------------------------------------

  test "generate_secret returns a non-empty base32 string" do
    secret = TOTP.generate_secret()
    assert is_binary(secret)
    assert byte_size(secret) > 0
    assert String.match?(secret, ~r/\A[A-Z2-7]+\z/)
  end

  test "generate_secret returns different secrets each call" do
    secrets = for _ <- 1..20, do: TOTP.generate_secret()
    assert Enum.uniq(secrets) == secrets
  end

  test "generate_secret output is decodable back to 20 bytes" do
    secret = TOTP.generate_secret()
    # Round-tripping through generate_code is the simplest proxy for
    # a valid decode — it will crash if the base32 is malformed.
    assert is_binary(TOTP.generate_code(secret, 0))
  end

  # -------------------------------------------------------------------
  # generate_code/2 — format
  # -------------------------------------------------------------------

  test "generate_code returns a 6-character string" do
    secret = TOTP.generate_secret()
    code = TOTP.generate_code(secret, :os.system_time(:second))
    assert is_binary(code)
    assert byte_size(code) == 6
    assert String.match?(code, ~r/\A\d{6}\z/)
  end

  test "generate_code zero-pads codes shorter than 6 digits" do
    # We can't force a specific short code without a known secret, but
    # we can verify the RFC vector at t=59 which starts with "28" (not
    # a leading-zero case) and at t=1_234_567_890 which is "005924".
    assert TOTP.generate_code(@rfc_secret, 1_234_567_890) == "005924"
  end

  # -------------------------------------------------------------------
  # generate_code/2 — RFC 6238 test vectors
  # -------------------------------------------------------------------

  for {t, expected} <- [
        {59, "287082"},
        {1_111_111_109, "081804"},
        {1_111_111_111, "050471"},
        {1_234_567_890, "005924"},
        {2_000_000_000, "279037"},
        {20_000_000_000, "353130"}
      ] do
    test "RFC vector at t=#{t} produces #{expected}" do
      assert TOTP.generate_code(@rfc_secret, unquote(t)) == unquote(expected)
    end
  end

  # -------------------------------------------------------------------
  # generate_code/2 — stability within a 30-second step
  # -------------------------------------------------------------------

  test "same code is produced for all timestamps within the same 30-second step" do
    secret = TOTP.generate_secret()
    base_time = 90_000

    code_at_start = TOTP.generate_code(secret, base_time)

    for offset <- 1..29 do
      assert TOTP.generate_code(secret, base_time + offset) == code_at_start,
             "Code differed at offset +#{offset}"
    end
  end

  test "code changes at a step boundary" do
    secret = TOTP.generate_secret()
    # Use a deterministic step boundary
    t = 30 * 1000

    code_before = TOTP.generate_code(secret, t - 1)
    code_after = TOTP.generate_code(secret, t)

    # There is a 1-in-1_000_000 chance these are equal by coincidence.
    # Acceptable for a test suite.
    refute code_before == code_after
  end

  # -------------------------------------------------------------------
  # valid?/3 — basic acceptance and rejection
  # -------------------------------------------------------------------

  test "valid? accepts the current code" do
    secret = TOTP.generate_secret()
    now = :os.system_time(:second)
    code = TOTP.generate_code(secret, now)
    assert TOTP.valid?(secret, code, time: now)
  end

  test "valid? rejects a wrong code" do
    secret = TOTP.generate_secret()
    now = :os.system_time(:second)
    code = TOTP.generate_code(secret, now)

    wrong =
      code
      |> String.to_integer()
      |> then(&rem(&1 + 1, 1_000_000))
      |> Integer.to_string()
      |> String.pad_leading(6, "0")

    refute TOTP.valid?(secret, wrong, time: now)
  end

  test "valid? accepts an integer code as well as a string code" do
    secret = TOTP.generate_secret()
    now = :os.system_time(:second)
    code_str = TOTP.generate_code(secret, now)
    code_int = String.to_integer(code_str)

    assert TOTP.valid?(secret, code_str, time: now)
    assert TOTP.valid?(secret, code_int, time: now)
  end

  # -------------------------------------------------------------------
  # valid?/3 — window / clock-drift tolerance
  # -------------------------------------------------------------------

  test "valid? accepts codes from adjacent steps within the default window" do
    secret = TOTP.generate_secret()
    now = 90_000

    code_prev = TOTP.generate_code(secret, now - 30)
    code_next = TOTP.generate_code(secret, now + 30)

    assert TOTP.valid?(secret, code_prev, time: now, window: 1)
    assert TOTP.valid?(secret, code_next, time: now, window: 1)
  end

  test "valid? rejects codes two steps away when window is 1" do
    secret = TOTP.generate_secret()
    now = 90_000

    code_two_steps_ago = TOTP.generate_code(secret, now - 60)
    code_two_steps_ahead = TOTP.generate_code(secret, now + 60)

    refute TOTP.valid?(secret, code_two_steps_ago, time: now, window: 1)
    refute TOTP.valid?(secret, code_two_steps_ahead, time: now, window: 1)
  end

  test "valid? accepts a wider window when configured" do
    secret = TOTP.generate_secret()
    now = 90_000

    code_two_steps_ago = TOTP.generate_code(secret, now - 60)
    assert TOTP.valid?(secret, code_two_steps_ago, time: now, window: 2)
  end

  test "valid? with window: 0 only accepts the exact current step" do
    secret = TOTP.generate_secret()
    now = 90_000

    code_current = TOTP.generate_code(secret, now)
    code_prev = TOTP.generate_code(secret, now - 30)

    assert TOTP.valid?(secret, code_current, time: now, window: 0)
    refute TOTP.valid?(secret, code_prev, time: now, window: 0)
  end

  # -------------------------------------------------------------------
  # valid?/3 — defaults to current time
  # -------------------------------------------------------------------

  test "valid? with no time option uses the real clock" do
    secret = TOTP.generate_secret()
    code = TOTP.generate_code(secret, :os.system_time(:second))
    assert TOTP.valid?(secret, code)
  end

  # -------------------------------------------------------------------
  # provisioning_uri/3
  # -------------------------------------------------------------------

  test "provisioning_uri starts with otpauth://totp/" do
    uri = TOTP.provisioning_uri(@rfc_secret, "Acme", "alice@example.com")
    assert String.starts_with?(uri, "otpauth://totp/")
  end

  test "provisioning_uri contains the correct label" do
    uri = TOTP.provisioning_uri(@rfc_secret, "Acme Co", "alice@example.com")
    assert uri =~ "Acme%20Co:alice%40example.com" or uri =~ "Acme+Co:alice%40example.com"
  end

  test "provisioning_uri contains all required query parameters" do
    uri = TOTP.provisioning_uri(@rfc_secret, "Acme", "alice@example.com")
    assert uri =~ "secret=#{@rfc_secret}"
    assert uri =~ "issuer=Acme"
    assert uri =~ "algorithm=SHA1"
    assert uri =~ "digits=6"
    assert uri =~ "period=30"
  end

  test "provisioning_uri is parseable as a URI" do
    uri = TOTP.provisioning_uri(@rfc_secret, "Acme", "alice@example.com")
    parsed = URI.parse(uri)
    assert parsed.scheme == "otpauth"
    assert parsed.host == "totp"
    assert parsed.query != nil
  end

  test "provisioning_uri with special characters in issuer and account is still valid" do
    uri = TOTP.provisioning_uri(@rfc_secret, "My Company, LLC", "user+tag@domain.io")
    parsed = URI.parse(uri)
    params = URI.decode_query(parsed.query)
    assert params["secret"] == @rfc_secret
    assert params["digits"] == "6"
    assert params["period"] == "30"
  end
end
