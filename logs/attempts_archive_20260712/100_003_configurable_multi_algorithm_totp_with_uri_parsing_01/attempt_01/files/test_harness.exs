defmodule TOTPTest do
  use ExUnit.Case, async: false

  # Canonical RFC 6238 SHA1 secret "12345678901234567890", base32-encoded.
  @secret "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"

  # RFC 6238 SHA1 test vectors at 8 digits.
  @sha1_8 [
    {59, "94287082"},
    {1_111_111_109, "07081804"},
    {1_111_111_111, "14050471"},
    {1_234_567_890, "89005924"},
    {2_000_000_000, "69279037"},
    {20_000_000_000, "65353130"}
  ]

  # The same vectors truncated to the default 6 digits.
  @sha1_6 [
    {59, "287082"},
    {1_111_111_109, "081804"},
    {1_234_567_890, "005924"},
    {20_000_000_000, "353130"}
  ]

  # -------------------------------------------------------------------
  # generate_secret/1
  # -------------------------------------------------------------------

  test "generate_secret returns a 32-character base32 string by default" do
    secret = TOTP.generate_secret()
    assert is_binary(secret)
    assert byte_size(secret) == 32
    assert String.match?(secret, ~r/\A[A-Z2-7]+\z/)
  end

  test "generate_secret returns different secrets each call" do
    secrets = for _ <- 1..20, do: TOTP.generate_secret()
    assert Enum.uniq(secrets) == secrets
  end

  # -------------------------------------------------------------------
  # generate_code/2 — RFC 6238 SHA1 vectors (8 and 6 digits)
  # -------------------------------------------------------------------

  for {t, expected} <- @sha1_8 do
    test "SHA1 8-digit vector at t=#{t} produces #{expected}" do
      assert TOTP.generate_code(@secret, time: unquote(t), digits: 8) == unquote(expected)
    end
  end

  for {t, expected} <- @sha1_6 do
    test "default SHA1 6-digit vector at t=#{t} produces #{expected}" do
      assert TOTP.generate_code(@secret, time: unquote(t)) == unquote(expected)
    end
  end

  test "generate_code defaults to a 6-digit code" do
    code = TOTP.generate_code(@secret, time: 59)
    assert byte_size(code) == 6
    assert String.match?(code, ~r/\A\d{6}\z/)
  end

  # -------------------------------------------------------------------
  # generate_code/2 — digit configurability
  # -------------------------------------------------------------------

  test "digits option controls the code length" do
    now = 1_234_567_890
    assert byte_size(TOTP.generate_code(@secret, time: now, digits: 6)) == 6
    assert byte_size(TOTP.generate_code(@secret, time: now, digits: 7)) == 7
    assert byte_size(TOTP.generate_code(@secret, time: now, digits: 8)) == 8
  end

  # -------------------------------------------------------------------
  # generate_code/2 — algorithm configurability
  # -------------------------------------------------------------------

  test "different algorithms produce distinct codes of the requested length" do
    t = 59
    s1 = TOTP.generate_code(@secret, time: t, algorithm: :sha1, digits: 8)
    s256 = TOTP.generate_code(@secret, time: t, algorithm: :sha256, digits: 8)
    s512 = TOTP.generate_code(@secret, time: t, algorithm: :sha512, digits: 8)

    assert byte_size(s256) == 8
    assert byte_size(s512) == 8
    assert s1 == "94287082"
    refute s256 == s1
    refute s512 == s1
    refute s256 == s512
  end

  test "each algorithm round-trips through valid?" do
    now = 1_234_567_890

    for alg <- [:sha1, :sha256, :sha512] do
      code = TOTP.generate_code(@secret, time: now, algorithm: alg)
      assert TOTP.valid?(@secret, code, time: now, algorithm: alg)
    end
  end

  # -------------------------------------------------------------------
  # generate_code/2 — period configurability
  # -------------------------------------------------------------------

  test "code is stable within a configured period and changes at the boundary" do
    t = 90_000
    code = TOTP.generate_code(@secret, time: t, period: 60)

    # 90_000 and 90_059 fall in the same 60-second step (step 1500).
    assert TOTP.generate_code(@secret, time: t + 59, period: 60) == code
    # 90_060 is step 1501.
    refute TOTP.generate_code(@secret, time: t + 60, period: 60) == code
  end

  # -------------------------------------------------------------------
  # valid?/3 — acceptance, rejection, and drift window
  # -------------------------------------------------------------------

  test "valid? accepts the current code and rejects a wrong one" do
    now = :os.system_time(:second)
    code = TOTP.generate_code(@secret, time: now)
    assert TOTP.valid?(@secret, code, time: now)
    refute TOTP.valid?(@secret, "000000", time: now)
  end

  test "valid? accepts an integer code" do
    now = 1_234_567_890
    # t=1_234_567_890 default 6-digit code is "005924".
    assert TOTP.valid?(@secret, 5924, time: now)
  end

  test "valid? tolerates adjacent steps within the default window" do
    now = 90_000
    prev = TOTP.generate_code(@secret, time: now - 30)
    next = TOTP.generate_code(@secret, time: now + 30)
    assert TOTP.valid?(@secret, prev, time: now, window: 1)
    assert TOTP.valid?(@secret, next, time: now, window: 1)
  end

  test "valid? with window 0 only accepts the exact step" do
    now = 90_000
    current = TOTP.generate_code(@secret, time: now)
    prev = TOTP.generate_code(@secret, time: now - 30)
    assert TOTP.valid?(@secret, current, time: now, window: 0)
    refute TOTP.valid?(@secret, prev, time: now, window: 0)
  end

  test "valid? honors the period option in its window" do
    t = 90_000
    prev_step = TOTP.generate_code(@secret, time: t - 60, period: 60)
    assert TOTP.valid?(@secret, prev_step, time: t, period: 60, window: 1)
  end

  # -------------------------------------------------------------------
  # provisioning_uri/4
  # -------------------------------------------------------------------

  test "provisioning_uri reflects default parameters" do
    uri = TOTP.provisioning_uri(@secret, "Acme", "bob@example.com")
    assert String.starts_with?(uri, "otpauth://totp/")
    params = URI.decode_query(URI.parse(uri).query)
    assert params["secret"] == @secret
    assert params["issuer"] == "Acme"
    assert params["algorithm"] == "SHA1"
    assert params["digits"] == "6"
    assert params["period"] == "30"
  end

  test "provisioning_uri reflects configured parameters" do
    uri =
      TOTP.provisioning_uri(@secret, "Acme", "alice@example.com",
        algorithm: :sha256,
        digits: 8,
        period: 60
      )

    parsed = URI.parse(uri)
    assert parsed.scheme == "otpauth"
    assert parsed.host == "totp"
    assert uri =~ "Acme:alice%40example.com"

    params = URI.decode_query(parsed.query)
    assert params["algorithm"] == "SHA256"
    assert params["digits"] == "8"
    assert params["period"] == "60"
    assert params["secret"] == @secret
  end

  # -------------------------------------------------------------------
  # parse_uri/1
  # -------------------------------------------------------------------

  test "parse_uri round-trips a configured provisioning URI" do
    uri =
      TOTP.provisioning_uri(@secret, "Acme", "alice@example.com",
        algorithm: :sha256,
        digits: 8,
        period: 60
      )

    assert {:ok, cfg} = TOTP.parse_uri(uri)
    assert cfg.secret == @secret
    assert cfg.issuer == "Acme"
    assert cfg.algorithm == :sha256
    assert cfg.digits == 8
    assert cfg.period == 60
  end

  test "parse_uri applies defaults for missing parameters" do
    assert {:ok, cfg} = TOTP.parse_uri("otpauth://totp/Acme:bob?secret=" <> @secret)
    assert cfg.secret == @secret
    assert cfg.algorithm == :sha1
    assert cfg.digits == 6
    assert cfg.period == 30
  end

  test "parse_uri rejects non-otpauth and non-totp URIs" do
    assert TOTP.parse_uri("https://example.com/foo?bar=1") == :error
    assert TOTP.parse_uri("otpauth://hotp/Acme:bob?secret=" <> @secret) == :error
  end
end
