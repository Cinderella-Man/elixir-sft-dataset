defmodule AuthenticatorURITest do
  use ExUnit.Case, async: false

  # RFC 6238 test seeds, base32-encoded (RFC 4648, unpadded).
  #   SHA1:   "12345678901234567890"                                             (20 bytes)
  #   SHA256: "12345678901234567890123456789012"                                 (32 bytes)
  #   SHA512: "1234567890123456789012345678901234567890123456789012345678901234" (64 bytes)
  @sha1_secret "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"
  @sha256_secret "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZA"
  @sha512_secret "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNA"

  defp uri(params) do
    query = URI.encode_query(params)
    "otpauth://totp/Acme:alice@example.com?" <> query
  end

  defp config!(params) do
    {:ok, config} = AuthenticatorURI.parse(uri(params))
    config
  end

  # ------------------------------------------------------------------
  # parse/1 — happy path and defaults
  # ------------------------------------------------------------------

  test "parse returns a full config map" do
    assert {:ok, config} =
             AuthenticatorURI.parse(
               "otpauth://totp/Acme:alice@example.com?secret=#{@sha1_secret}&algorithm=SHA256&digits=8&period=60"
             )

    assert config == %{
             issuer: "Acme",
             account: "alice@example.com",
             secret: @sha1_secret,
             algorithm: :sha256,
             digits: 8,
             period: 60
           }
  end

  test "parse applies defaults for algorithm, digits and period" do
    config = config!(secret: @sha1_secret)
    assert config.algorithm == :sha1
    assert config.digits == 6
    assert config.period == 30
  end

  test "parse accepts a label with no issuer and no issuer param" do
    assert {:ok, config} =
             AuthenticatorURI.parse("otpauth://totp/alice@example.com?secret=#{@sha1_secret}")

    assert config.issuer == nil
    assert config.account == "alice@example.com"
  end

  test "parse takes the issuer from the query param when the label has none" do
    assert {:ok, config} =
             AuthenticatorURI.parse(
               "otpauth://totp/alice@example.com?secret=#{@sha1_secret}&issuer=Acme"
             )

    assert config.issuer == "Acme"
    assert config.account == "alice@example.com"
  end

  test "parse percent-decodes the label" do
    assert {:ok, config} =
             AuthenticatorURI.parse(
               "otpauth://totp/Acme%20Co:alice%40example.com?secret=#{@sha1_secret}"
             )

    assert config.issuer == "Acme Co"
    assert config.account == "alice@example.com"
  end

  test "parse strips a single space after the label colon" do
    assert {:ok, config} =
             AuthenticatorURI.parse("otpauth://totp/Acme:%20alice?secret=#{@sha1_secret}")

    assert config.issuer == "Acme"
    assert config.account == "alice"
  end

  test "parse accepts a matching issuer in both label and query param" do
    assert {:ok, config} =
             AuthenticatorURI.parse(
               "otpauth://totp/Acme%20Co:alice?secret=#{@sha1_secret}&issuer=Acme+Co"
             )

    assert config.issuer == "Acme Co"
  end

  test "parse normalizes a lowercase, padded, whitespace-y secret" do
    raw = String.downcase(@sha1_secret) <> "===="

    assert {:ok, config} =
             AuthenticatorURI.parse("otpauth://totp/Acme:alice?secret=#{URI.encode(raw)}")

    assert config.secret == @sha1_secret
  end

  test "parse accepts each supported algorithm spelling case-insensitively" do
    assert config!(secret: @sha1_secret, algorithm: "sha1").algorithm == :sha1
    assert config!(secret: @sha256_secret, algorithm: "Sha256").algorithm == :sha256
    assert config!(secret: @sha512_secret, algorithm: "SHA512").algorithm == :sha512
  end

  test "parse accepts digits 6, 7 and 8" do
    assert config!(secret: @sha1_secret, digits: "6").digits == 6
    assert config!(secret: @sha1_secret, digits: "7").digits == 7
    assert config!(secret: @sha1_secret, digits: "8").digits == 8
  end

  # ------------------------------------------------------------------
  # parse/1 — error semantics
  # ------------------------------------------------------------------

  test "parse rejects a non-otpauth scheme" do
    assert AuthenticatorURI.parse("https://totp/Acme:alice?secret=#{@sha1_secret}") ==
             {:error, :invalid_scheme}
  end

  test "parse rejects a non-binary argument" do
    assert AuthenticatorURI.parse(nil) == {:error, :invalid_scheme}
    assert AuthenticatorURI.parse(:otpauth) == {:error, :invalid_scheme}
  end

  test "parse rejects the hotp type" do
    assert AuthenticatorURI.parse("otpauth://hotp/Acme:alice?secret=#{@sha1_secret}&counter=1") ==
             {:error, :unsupported_type}
  end

  test "parse rejects an empty or malformed label" do
    assert AuthenticatorURI.parse("otpauth://totp/?secret=#{@sha1_secret}") ==
             {:error, :missing_label}

    assert AuthenticatorURI.parse("otpauth://totp/Acme:?secret=#{@sha1_secret}") ==
             {:error, :missing_label}

    assert AuthenticatorURI.parse("otpauth://totp/:alice?secret=#{@sha1_secret}") ==
             {:error, :missing_label}
  end

  test "parse rejects a missing secret" do
    assert AuthenticatorURI.parse("otpauth://totp/Acme:alice?issuer=Acme") ==
             {:error, :missing_secret}
  end

  test "parse rejects a secret with non-base32 characters" do
    assert AuthenticatorURI.parse("otpauth://totp/Acme:alice?secret=ABC1DEF") ==
             {:error, :invalid_secret}

    assert AuthenticatorURI.parse("otpauth://totp/Acme:alice?secret=ABC%21DEF") ==
             {:error, :invalid_secret}
  end

  test "parse rejects a secret that normalizes to the empty string" do
    assert AuthenticatorURI.parse("otpauth://totp/Acme:alice?secret=%3D%3D%3D") ==
             {:error, :invalid_secret}
  end

  test "parse rejects an issuer mismatch between label and query param" do
    assert AuthenticatorURI.parse("otpauth://totp/Acme:alice?secret=#{@sha1_secret}&issuer=Other") ==
             {:error, :issuer_mismatch}
  end

  test "parse rejects an unsupported algorithm" do
    assert AuthenticatorURI.parse(
             "otpauth://totp/Acme:alice?secret=#{@sha1_secret}&algorithm=MD5"
           ) == {:error, :unsupported_algorithm}
  end

  test "parse rejects unsupported digit counts" do
    assert AuthenticatorURI.parse("otpauth://totp/Acme:alice?secret=#{@sha1_secret}&digits=9") ==
             {:error, :invalid_digits}

    assert AuthenticatorURI.parse("otpauth://totp/Acme:alice?secret=#{@sha1_secret}&digits=5") ==
             {:error, :invalid_digits}

    assert AuthenticatorURI.parse("otpauth://totp/Acme:alice?secret=#{@sha1_secret}&digits=six") ==
             {:error, :invalid_digits}

    assert AuthenticatorURI.parse("otpauth://totp/Acme:alice?secret=#{@sha1_secret}&digits=6x") ==
             {:error, :invalid_digits}
  end

  test "parse rejects invalid periods" do
    assert AuthenticatorURI.parse("otpauth://totp/Acme:alice?secret=#{@sha1_secret}&period=0") ==
             {:error, :invalid_period}

    assert AuthenticatorURI.parse("otpauth://totp/Acme:alice?secret=#{@sha1_secret}&period=-30") ==
             {:error, :invalid_period}

    assert AuthenticatorURI.parse("otpauth://totp/Acme:alice?secret=#{@sha1_secret}&period=abc") ==
             {:error, :invalid_period}
  end

  test "parse accepts a non-default period" do
    assert config!(secret: @sha1_secret, period: "90").period == 90
  end

  # ------------------------------------------------------------------
  # code_at/2 — RFC 6238 vectors (8 digits, period 30)
  # ------------------------------------------------------------------

  for {t, expected} <- [
        {59, "94287082"},
        {1_111_111_109, "07081804"},
        {1_111_111_111, "14050471"},
        {1_234_567_890, "89005924"},
        {2_000_000_000, "69279037"},
        {20_000_000_000, "65353130"}
      ] do
    test "SHA1 8-digit RFC vector at t=#{t}" do
      config = config!(secret: @sha1_secret, algorithm: "SHA1", digits: "8")
      assert AuthenticatorURI.code_at(config, unquote(t)) == unquote(expected)
    end
  end

  for {t, expected} <- [
        {59, "46119246"},
        {1_111_111_109, "68084774"},
        {1_111_111_111, "67062674"},
        {1_234_567_890, "91819424"},
        {2_000_000_000, "90698825"},
        {20_000_000_000, "77737706"}
      ] do
    test "SHA256 8-digit RFC vector at t=#{t}" do
      config = config!(secret: @sha256_secret, algorithm: "SHA256", digits: "8")
      assert AuthenticatorURI.code_at(config, unquote(t)) == unquote(expected)
    end
  end

  for {t, expected} <- [
        {59, "90693936"},
        {1_111_111_109, "25091201"},
        {1_111_111_111, "99943326"},
        {1_234_567_890, "93441116"},
        {2_000_000_000, "38618901"},
        {20_000_000_000, "47863826"}
      ] do
    test "SHA512 8-digit RFC vector at t=#{t}" do
      config = config!(secret: @sha512_secret, algorithm: "SHA512", digits: "8")
      assert AuthenticatorURI.code_at(config, unquote(t)) == unquote(expected)
    end
  end

  # ------------------------------------------------------------------
  # code_at/2 — digits and period handling
  # ------------------------------------------------------------------

  test "6-digit codes are the truncation of the same counter" do
    config = config!(secret: @sha1_secret)
    assert AuthenticatorURI.code_at(config, 1_234_567_890) == "005924"
    assert AuthenticatorURI.code_at(config, 59) == "287082"
  end

  test "7-digit codes are the truncation of the same counter" do
    config = config!(secret: @sha1_secret, digits: "7")
    assert AuthenticatorURI.code_at(config, 1_234_567_890) == "9005924"
    assert AuthenticatorURI.code_at(config, 59) == "4287082"
  end

  test "code length always equals the configured digit count" do
    for d <- ["6", "7", "8"] do
      config = config!(secret: @sha1_secret, digits: d)
      code = AuthenticatorURI.code_at(config, 1_234_567_890)
      assert byte_size(code) == config.digits
      assert String.match?(code, ~r/\A\d+\z/)
    end
  end

  test "code is stable across a period and changes at the boundary" do
    config = config!(secret: @sha1_secret)

    assert AuthenticatorURI.code_at(config, 1_111_111_111) ==
             AuthenticatorURI.code_at(config, 1_111_111_139)

    refute AuthenticatorURI.code_at(config, 1_111_111_109) ==
             AuthenticatorURI.code_at(config, 1_111_111_111)
  end

  test "a different period yields a different counter" do
    p30 = config!(secret: @sha1_secret)
    p60 = config!(secret: @sha1_secret, period: "60")

    # div(59, 30) == 1 while div(59, 60) == 0, so the codes come from
    # different counters.
    assert AuthenticatorURI.code_at(p30, 59) == "287082"
    assert AuthenticatorURI.code_at(p60, 59) == AuthenticatorURI.code_at(p30, 0)
  end

  # ------------------------------------------------------------------
  # seconds_remaining/2
  # ------------------------------------------------------------------

  test "seconds_remaining counts down within a period" do
    config = config!(secret: @sha1_secret)
    assert AuthenticatorURI.seconds_remaining(config, 1_111_111_111) == 29
    assert AuthenticatorURI.seconds_remaining(config, 1_111_111_139) == 1
  end

  test "seconds_remaining returns the full period on a boundary" do
    config = config!(secret: @sha1_secret)
    assert AuthenticatorURI.seconds_remaining(config, 1_111_111_110) == 30
  end

  test "seconds_remaining honours a custom period" do
    config = config!(secret: @sha1_secret, period: "60")
    assert AuthenticatorURI.seconds_remaining(config, 1_111_111_111) == 29
    assert AuthenticatorURI.seconds_remaining(config, 1_111_111_080) == 60
  end

  # ------------------------------------------------------------------
  # verify/3
  # ------------------------------------------------------------------

  test "verify accepts the code for the current step" do
    config = config!(secret: @sha1_secret)
    assert AuthenticatorURI.verify(config, "005924", 1_234_567_890)
    assert AuthenticatorURI.verify(config, AuthenticatorURI.code_at(config, 59), 59)
  end

  test "verify accepts an integer code, zero-padding it" do
    config = config!(secret: @sha1_secret)
    assert AuthenticatorURI.verify(config, 5924, 1_234_567_890)
  end

  test "verify rejects a wrong code" do
    config = config!(secret: @sha1_secret)
    refute AuthenticatorURI.verify(config, "999999", 1_234_567_890)
    refute AuthenticatorURI.verify(config, "12345", 1_234_567_890)
  end

  test "verify has no drift window: adjacent steps are rejected" do
    config = config!(secret: @sha1_secret)

    previous = AuthenticatorURI.code_at(config, 1_111_111_109)
    current = AuthenticatorURI.code_at(config, 1_111_111_111)
    following = AuthenticatorURI.code_at(config, 1_111_111_141)

    assert AuthenticatorURI.verify(config, current, 1_111_111_111)
    refute AuthenticatorURI.verify(config, previous, 1_111_111_111)
    refute AuthenticatorURI.verify(config, following, 1_111_111_111)
  end

  test "verify works for 8-digit SHA512 configs" do
    config = config!(secret: @sha512_secret, algorithm: "SHA512", digits: "8")
    assert AuthenticatorURI.verify(config, "93441116", 1_234_567_890)
    refute AuthenticatorURI.verify(config, "93441117", 1_234_567_890)
  end

  test "parse rejects a period that is not the exact decimal string of the integer" do
    assert AuthenticatorURI.parse("otpauth://totp/Acme:alice?secret=#{@sha1_secret}&period=%2B30") ==
             {:error, :invalid_period}

    assert AuthenticatorURI.parse("otpauth://totp/Acme:alice?secret=#{@sha1_secret}&period=030") ==
             {:error, :invalid_period}
  end

  test "parse strips embedded whitespace from the secret" do
    raw = "gezd gnbv gy3t qojq\tGEZD GNBV GY3T QOJQ = "

    assert {:ok, config} =
             AuthenticatorURI.parse(
               "otpauth://totp/Acme:alice?secret=" <> URI.encode_www_form(raw)
             )

    assert config.secret == @sha1_secret
    assert AuthenticatorURI.code_at(config, 1_234_567_890) == "005924"
  end

  test "verify rejects a code longer than the configured digit count" do
    config = config!(secret: @sha1_secret)

    refute AuthenticatorURI.verify(config, "0005924", 1_234_567_890)
    refute AuthenticatorURI.verify(config, 1_005_924, 1_234_567_890)
  end

  test "parse accepts an uppercase scheme" do
    assert {:ok, config} =
             AuthenticatorURI.parse("OTPAUTH://totp/Acme:alice?secret=#{@sha1_secret}")

    assert config.account == "alice"
  end

  test "parse accepts an uppercase totp type" do
    assert {:ok, config} =
             AuthenticatorURI.parse("otpauth://TOTP/Acme:alice?secret=#{@sha1_secret}")

    assert config.issuer == "Acme"
  end

  test "parse rejects a URI with no query string at all" do
    assert AuthenticatorURI.parse("otpauth://totp/Acme:alice") == {:error, :missing_secret}
  end
end
