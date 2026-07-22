defmodule FlexTOTPTest do
  use ExUnit.Case, async: false

  # RFC 6238 SHA1 seed: ASCII "12345678901234567890", base32-encoded.
  @sha1_secret "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"

  # -------------------------------------------------------------------
  # generate_secret/1
  # -------------------------------------------------------------------

  test "generate_secret returns a base32 string" do
    secret = FlexTOTP.generate_secret()
    assert String.match?(secret, ~r/\A[A-Z2-7]+\z/)
  end

  test "generate_secret returns unique values" do
    secrets = for _ <- 1..20, do: FlexTOTP.generate_secret()
    assert Enum.uniq(secrets) == secrets
  end

  # -------------------------------------------------------------------
  # generate_code/2 — RFC 6238 SHA1 vectors (8-digit and default 6-digit)
  # -------------------------------------------------------------------

  for {t, expected8} <- [
        {59, "94287082"},
        {1_111_111_109, "07081804"},
        {1_111_111_111, "14050471"},
        {1_234_567_890, "89005924"},
        {2_000_000_000, "69279037"},
        {20_000_000_000, "65353130"}
      ] do
    test "SHA1 8-digit vector at t=#{t} produces #{expected8}" do
      assert FlexTOTP.generate_code(@sha1_secret, time: unquote(t), digits: 8) ==
               unquote(expected8)
    end

    test "SHA1 6-digit default at t=#{t} is the last 6 digits of #{expected8}" do
      expected6 = String.slice(unquote(expected8), -6, 6)
      assert FlexTOTP.generate_code(@sha1_secret, time: unquote(t)) == expected6
    end
  end

  # -------------------------------------------------------------------
  # generate_code/2 — option behavior
  # -------------------------------------------------------------------

  test "digits option controls code length" do
    assert byte_size(FlexTOTP.generate_code(@sha1_secret, time: 59, digits: 6)) == 6
    assert byte_size(FlexTOTP.generate_code(@sha1_secret, time: 59, digits: 8)) == 8
  end

  test "code is stable within a period and changes at the boundary" do
    secret = FlexTOTP.generate_secret()
    code = FlexTOTP.generate_code(secret, time: 90_000, period: 30)
    assert FlexTOTP.generate_code(secret, time: 90_015, period: 30) == code
    refute FlexTOTP.generate_code(secret, time: 90_030, period: 30) == code
  end

  test "changing the algorithm changes the code for the same secret/time" do
    s1 = FlexTOTP.generate_code(@sha1_secret, time: 59, algorithm: :sha1)
    s256 = FlexTOTP.generate_code(@sha1_secret, time: 59, algorithm: :sha256)
    s512 = FlexTOTP.generate_code(@sha1_secret, time: 59, algorithm: :sha512)
    assert s1 != s256
    assert s1 != s512
    assert s256 != s512
  end

  test "changing the period changes the effective step and code" do
    secret = FlexTOTP.generate_secret()
    c30 = FlexTOTP.generate_code(secret, time: 90_000, period: 30)
    c60 = FlexTOTP.generate_code(secret, time: 90_000, period: 60)
    # step 3000 vs step 1500 — overwhelmingly different codes.
    refute c30 == c60
  end

  # -------------------------------------------------------------------
  # valid?/3 — round-trip across algorithms and options
  # -------------------------------------------------------------------

  for algorithm <- [:sha1, :sha256, :sha512] do
    test "valid? accepts a freshly generated #{algorithm} code" do
      secret = FlexTOTP.generate_secret()
      now = 90_000
      code = FlexTOTP.generate_code(secret, time: now, algorithm: unquote(algorithm))

      assert FlexTOTP.valid?(secret, code, time: now, algorithm: unquote(algorithm))
    end
  end

  test "valid? tolerates ±1 step of drift by default" do
    secret = FlexTOTP.generate_secret()
    now = 90_000
    prev = FlexTOTP.generate_code(secret, time: now - 30)
    next = FlexTOTP.generate_code(secret, time: now + 30)

    assert FlexTOTP.valid?(secret, prev, time: now)
    assert FlexTOTP.valid?(secret, next, time: now)
  end

  test "valid? rejects codes two steps away with the default window" do
    secret = FlexTOTP.generate_secret()
    now = 90_000
    far = FlexTOTP.generate_code(secret, time: now - 60)
    refute FlexTOTP.valid?(secret, far, time: now)
  end

  test "valid? accepts an integer code" do
    secret = FlexTOTP.generate_secret()
    now = 90_000
    code = FlexTOTP.generate_code(secret, time: now)
    assert FlexTOTP.valid?(secret, String.to_integer(code), time: now)
  end

  test "valid? respects digits when validating" do
    secret = FlexTOTP.generate_secret()
    now = 90_000
    code8 = FlexTOTP.generate_code(secret, time: now, digits: 8)
    assert FlexTOTP.valid?(secret, code8, time: now, digits: 8)
  end

  # -------------------------------------------------------------------
  # provisioning_uri/4
  # -------------------------------------------------------------------

  test "provisioning_uri encodes chosen algorithm, digits and period" do
    uri =
      FlexTOTP.provisioning_uri(@sha1_secret, "Acme", "alice@example.com",
        algorithm: :sha256,
        digits: 8,
        period: 60
      )

    assert String.starts_with?(uri, "otpauth://totp/")
    assert uri =~ "secret=#{@sha1_secret}"
    assert uri =~ "algorithm=SHA256"
    assert uri =~ "digits=8"
    assert uri =~ "period=60"
  end

  test "provisioning_uri defaults to SHA1/6/30" do
    uri = FlexTOTP.provisioning_uri(@sha1_secret, "Acme", "alice@example.com")
    assert uri =~ "algorithm=SHA1"
    assert uri =~ "digits=6"
    assert uri =~ "period=30"
  end

  # -------------------------------------------------------------------
  # parse_uri/1
  # -------------------------------------------------------------------

  test "parse_uri round-trips a provisioning URI" do
    uri =
      FlexTOTP.provisioning_uri(@sha1_secret, "Acme Co", "alice@example.com",
        algorithm: :sha512,
        digits: 8,
        period: 45
      )

    assert {:ok, cfg} = FlexTOTP.parse_uri(uri)
    assert cfg.type == "totp"
    assert cfg.secret == @sha1_secret
    assert cfg.issuer == "Acme Co"
    assert cfg.account_name == "alice@example.com"
    assert cfg.algorithm == :sha512
    assert cfg.digits == 8
    assert cfg.period == 45
  end

  test "parse_uri applies documented defaults for missing parameters" do
    uri = "otpauth://totp/Acme:bob?secret=#{@sha1_secret}&issuer=Acme"
    assert {:ok, cfg} = FlexTOTP.parse_uri(uri)
    assert cfg.algorithm == :sha1
    assert cfg.digits == 6
    assert cfg.period == 30
    assert cfg.account_name == "bob"
    assert cfg.issuer == "Acme"
  end

  test "parse_uri returns :error for a non-otpauth string" do
    assert FlexTOTP.parse_uri("https://example.com/x") == :error
    assert FlexTOTP.parse_uri("not a uri") == :error
  end
end
