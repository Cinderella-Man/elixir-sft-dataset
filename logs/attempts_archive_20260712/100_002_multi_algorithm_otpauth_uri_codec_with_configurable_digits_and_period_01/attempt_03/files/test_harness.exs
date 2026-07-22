defmodule OTPAuthTest do
  use ExUnit.Case, async: false

  # RFC 6238 Appendix B seeds. We build the base32 form with the test-local
  # Base module (the implementation under test must roll its own base32).
  @seed_sha1 "12345678901234567890"
  @seed_sha256 "12345678901234567890123456789012"
  @seed_sha512 "1234567890123456789012345678901234567890123456789012345678901234"

  @secret_sha1 Base.encode32(@seed_sha1, padding: false)
  @secret_sha256 Base.encode32(@seed_sha256, padding: false)
  @secret_sha512 Base.encode32(@seed_sha512, padding: false)

  # {timestamp, sha1_8digit, sha256_8digit, sha512_8digit}
  @rfc_vectors [
    {59, "94287082", "46119246", "90693936"},
    {1_111_111_109, "07081804", "68084774", "25091201"},
    {1_111_111_111, "14050471", "67062674", "99943326"},
    {1_234_567_890, "89005924", "91819424", "93441116"},
    {2_000_000_000, "69279037", "90698825", "38618901"},
    {20_000_000_000, "65353130", "77737706", "47863826"}
  ]

  defp cfg(overrides \\ []) do
    Enum.into(overrides, %{secret: @secret_sha1})
  end

  # Last `count` characters of an ASCII code string.
  defp last_digits(code, count) do
    binary_part(code, byte_size(code) - count, count)
  end

  # -------------------------------------------------------------------
  # generate_secret/1
  # -------------------------------------------------------------------

  test "generate_secret returns an unpadded uppercase base32 string" do
    secret = OTPAuth.generate_secret()
    assert is_binary(secret)
    assert String.match?(secret, ~r/\A[A-Z2-7]+\z/)
  end

  test "generate_secret defaults to 20 bytes of entropy" do
    assert {:ok, bin} = OTPAuth.decode_secret(OTPAuth.generate_secret())
    assert byte_size(bin) == 20
  end

  test "generate_secret honours an explicit byte length" do
    assert {:ok, bin} = OTPAuth.decode_secret(OTPAuth.generate_secret(32))
    assert byte_size(bin) == 32
  end

  test "generate_secret returns distinct secrets" do
    secrets = for _ <- 1..20, do: OTPAuth.generate_secret()
    assert Enum.uniq(secrets) == secrets
  end

  # -------------------------------------------------------------------
  # decode_secret/1
  # -------------------------------------------------------------------

  test "decode_secret decodes a canonical secret" do
    assert OTPAuth.decode_secret(@secret_sha1) == {:ok, @seed_sha1}
  end

  test "decode_secret accepts lowercase input" do
    assert OTPAuth.decode_secret(String.downcase(@secret_sha1)) == {:ok, @seed_sha1}
  end

  test "decode_secret ignores whitespace groupings" do
    spaced =
      @secret_sha1
      |> String.graphemes()
      |> Enum.chunk_every(4)
      |> Enum.map_join(" ", &Enum.join/1)

    assert OTPAuth.decode_secret(spaced) == {:ok, @seed_sha1}
  end

  test "decode_secret ignores trailing padding characters" do
    assert OTPAuth.decode_secret(@secret_sha1 <> "======") == {:ok, @seed_sha1}
  end

  test "decode_secret rejects characters outside the base32 alphabet" do
    assert OTPAuth.decode_secret("GEZDGNBV1") == {:error, :invalid_secret}
    assert OTPAuth.decode_secret("GEZD-GNBV") == {:error, :invalid_secret}
  end

  test "decode_secret rejects a secret with fewer than 8 bits of data" do
    assert OTPAuth.decode_secret("") == {:error, :invalid_secret}
    assert OTPAuth.decode_secret("=") == {:error, :invalid_secret}
    assert OTPAuth.decode_secret("A") == {:error, :invalid_secret}
  end

  # -------------------------------------------------------------------
  # generate_code/2 — RFC 6238 vectors, all three algorithms, 8 digits
  # -------------------------------------------------------------------

  test "RFC 6238 vectors for SHA1 with 8 digits" do
    for {t, expected, _, _} <- @rfc_vectors do
      config = %{secret: @secret_sha1, algorithm: :sha1, digits: 8, period: 30}
      assert OTPAuth.generate_code(config, t) == expected
    end
  end

  test "RFC 6238 vectors for SHA256 with 8 digits" do
    for {t, _, expected, _} <- @rfc_vectors do
      config = %{secret: @secret_sha256, algorithm: :sha256, digits: 8, period: 30}
      assert OTPAuth.generate_code(config, t) == expected
    end
  end

  test "RFC 6238 vectors for SHA512 with 8 digits" do
    for {t, _, _, expected} <- @rfc_vectors do
      config = %{secret: @secret_sha512, algorithm: :sha512, digits: 8, period: 30}
      assert OTPAuth.generate_code(config, t) == expected
    end
  end

  # -------------------------------------------------------------------
  # digits — modulo 10^digits means shorter codes are suffixes
  # -------------------------------------------------------------------

  test "6-digit codes are the low 6 digits of the 8-digit code" do
    for {t, sha1_8, sha256_8, sha512_8} <- @rfc_vectors do
      assert OTPAuth.generate_code(%{secret: @secret_sha1, digits: 6}, t) ==
               last_digits(sha1_8, 6)

      assert OTPAuth.generate_code(
               %{secret: @secret_sha256, algorithm: :sha256, digits: 6},
               t
             ) == last_digits(sha256_8, 6)

      assert OTPAuth.generate_code(
               %{secret: @secret_sha512, algorithm: :sha512, digits: 6},
               t
             ) == last_digits(sha512_8, 6)
    end
  end

  test "7-digit codes are the low 7 digits of the 8-digit code" do
    for {t, sha1_8, _, _} <- @rfc_vectors do
      assert OTPAuth.generate_code(%{secret: @secret_sha1, digits: 7}, t) ==
               last_digits(sha1_8, 7)
    end
  end

  test "codes are zero-padded to exactly the configured digit count" do
    # RFC SHA1 vector at t=1_234_567_890 is 89005924 -> 6-digit form has leading zeros.
    assert OTPAuth.generate_code(%{secret: @secret_sha1, digits: 6}, 1_234_567_890) == "005924"
    assert OTPAuth.generate_code(%{secret: @secret_sha1, digits: 8}, 1_111_111_109) == "07081804"

    for digits <- [6, 7, 8] do
      code = OTPAuth.generate_code(%{secret: @secret_sha1, digits: digits}, 59)
      assert String.length(code) == digits
      assert String.match?(code, ~r/\A\d+\z/)
    end
  end

  # -------------------------------------------------------------------
  # defaults
  # -------------------------------------------------------------------

  test "a config with only a secret defaults to SHA1 / 6 digits / 30 seconds" do
    minimal = %{secret: @secret_sha1}
    explicit = %{secret: @secret_sha1, algorithm: :sha1, digits: 6, period: 30}

    for t <- [59, 1_111_111_111, 2_000_000_000] do
      assert OTPAuth.generate_code(minimal, t) == OTPAuth.generate_code(explicit, t)
    end

    assert OTPAuth.generate_code(minimal, 59) == "287082"
  end

  # -------------------------------------------------------------------
  # period
  # -------------------------------------------------------------------

  test "the code is stable inside a period and changes at the boundary" do
    config = %{secret: @secret_sha1, period: 90}
    at_start = OTPAuth.generate_code(config, 900)

    for offset <- [1, 45, 89] do
      assert OTPAuth.generate_code(config, 900 + offset) == at_start
    end

    refute OTPAuth.generate_code(config, 990) == at_start
  end

  test "codes depend only on the time step, so period and time scale together" do
    # step = div(time, period): div(120, 60) == div(60, 30) == 2
    assert OTPAuth.generate_code(%{secret: @secret_sha1, period: 60}, 120) ==
             OTPAuth.generate_code(%{secret: @secret_sha1, period: 30}, 60)
  end

  # -------------------------------------------------------------------
  # generate_code/2 — invalid secret
  # -------------------------------------------------------------------

  test "generate_code raises ArgumentError for an invalid base32 secret" do
    assert_raise ArgumentError, fn ->
      OTPAuth.generate_code(%{secret: "not-base32!"}, 0)
    end
  end

  # -------------------------------------------------------------------
  # valid?/3
  # -------------------------------------------------------------------

  test "valid? accepts the current code and rejects a wrong one" do
    config = cfg()
    now = 90_000
    code = OTPAuth.generate_code(config, now)

    assert OTPAuth.valid?(config, code, time: now)

    wrong =
      code
      |> String.to_integer()
      |> Kernel.+(1)
      |> rem(1_000_000)
      |> Integer.to_string()
      |> String.pad_leading(6, "0")

    refute OTPAuth.valid?(config, wrong, time: now)
  end

  test "valid? accepts an integer code, zero-padding it to the digit count" do
    config = %{secret: @secret_sha1, digits: 6}
    # t=1_234_567_890 -> "005924"
    assert OTPAuth.valid?(config, 5924, time: 1_234_567_890, window: 0)
    assert OTPAuth.valid?(config, "005924", time: 1_234_567_890, window: 0)
  end

  test "valid? honours the default window of one step in each direction" do
    config = cfg()
    now = 90_000

    assert OTPAuth.valid?(config, OTPAuth.generate_code(config, now - 30), time: now)
    assert OTPAuth.valid?(config, OTPAuth.generate_code(config, now + 30), time: now)
    refute OTPAuth.valid?(config, OTPAuth.generate_code(config, now - 60), time: now)
    refute OTPAuth.valid?(config, OTPAuth.generate_code(config, now + 60), time: now)
  end

  test "valid? window is measured in units of the configured period" do
    config = %{secret: @secret_sha1, period: 90}
    now = 900

    assert OTPAuth.valid?(config, OTPAuth.generate_code(config, now - 90), time: now, window: 1)
    refute OTPAuth.valid?(config, OTPAuth.generate_code(config, now - 180), time: now, window: 1)
    assert OTPAuth.valid?(config, OTPAuth.generate_code(config, now - 180), time: now, window: 2)
  end

  test "valid? with window 0 accepts only the exact step" do
    config = cfg()
    now = 90_000

    assert OTPAuth.valid?(config, OTPAuth.generate_code(config, now), time: now, window: 0)
    refute OTPAuth.valid?(config, OTPAuth.generate_code(config, now - 30), time: now, window: 0)
  end

  test "valid? defaults to the current system clock" do
    config = %{secret: @secret_sha1, algorithm: :sha512, digits: 8}
    code = OTPAuth.generate_code(config, :os.system_time(:second))
    assert OTPAuth.valid?(config, code)
  end

  # -------------------------------------------------------------------
  # build_uri/1
  # -------------------------------------------------------------------

  test "build_uri produces an otpauth totp URI with the issuer:account label" do
    uri =
      OTPAuth.build_uri(%{
        secret: @secret_sha1,
        issuer: "Acme",
        account_name: "alice@example.com"
      })

    assert String.starts_with?(uri, "otpauth://totp/")
    parsed = URI.parse(uri)
    assert parsed.scheme == "otpauth"
    assert parsed.host == "totp"
    assert URI.decode(String.trim_leading(parsed.path, "/")) == "Acme:alice@example.com"
  end

  test "build_uri materializes the default algorithm, digits and period" do
    uri =
      OTPAuth.build_uri(%{
        secret: @secret_sha1,
        issuer: "Acme",
        account_name: "alice"
      })

    params = uri |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
    assert params["secret"] == @secret_sha1
    assert params["issuer"] == "Acme"
    assert params["algorithm"] == "SHA1"
    assert params["digits"] == "6"
    assert params["period"] == "30"
  end

  test "build_uri emits the configured algorithm in uppercase plus digits and period" do
    uri =
      OTPAuth.build_uri(%{
        secret: @secret_sha512,
        issuer: "Acme",
        account_name: "alice",
        algorithm: :sha512,
        digits: 8,
        period: 60
      })

    params = uri |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
    assert params["algorithm"] == "SHA512"
    assert params["digits"] == "8"
    assert params["period"] == "60"
  end

  test "build_uri emits query parameters in the documented order" do
    uri =
      OTPAuth.build_uri(%{secret: @secret_sha1, issuer: "Acme", account_name: "alice"})

    query = uri |> URI.parse() |> Map.fetch!(:query)
    keys = query |> String.split("&") |> Enum.map(&(&1 |> String.split("=") |> hd()))
    assert keys == ["secret", "issuer", "algorithm", "digits", "period"]
  end

  test "build_uri URI-encodes special characters in the label" do
    uri =
      OTPAuth.build_uri(%{
        secret: @secret_sha1,
        issuer: "My Company, LLC",
        account_name: "user+tag@domain.io"
      })

    parsed = URI.parse(uri)
    refute parsed.path =~ " "

    assert URI.decode(String.trim_leading(parsed.path, "/")) ==
             "My Company, LLC:user+tag@domain.io"
  end

  # -------------------------------------------------------------------
  # parse_uri/1 — happy paths
  # -------------------------------------------------------------------

  test "parse_uri fills in defaults for absent parameters" do
    assert {:ok, config} =
             OTPAuth.parse_uri("otpauth://totp/Acme:alice?secret=#{@secret_sha1}")

    assert config == %{
             secret: @secret_sha1,
             issuer: "Acme",
             account_name: "alice",
             algorithm: :sha1,
             digits: 6,
             period: 30
           }
  end

  test "parse_uri reads algorithm case-insensitively, digits and period" do
    uri =
      "otpauth://totp/Acme:alice?secret=#{@secret_sha256}&algorithm=sha256&digits=8&period=60"

    assert {:ok, config} = OTPAuth.parse_uri(uri)
    assert config.algorithm == :sha256
    assert config.digits == 8
    assert config.period == 60
  end

  test "parse_uri percent-decodes the label and trims a leading space from the account" do
    assert {:ok, config} =
             OTPAuth.parse_uri(
               "otpauth://totp/Acme%20Co:%20alice%40example.com?secret=#{@secret_sha1}"
             )

    assert config.issuer == "Acme Co"
    assert config.account_name == "alice@example.com"
  end

  test "parse_uri splits the label at the first colon only" do
    assert {:ok, config} =
             OTPAuth.parse_uri("otpauth://totp/Acme:a:b:c?secret=#{@secret_sha1}")

    assert config.issuer == "Acme"
    assert config.account_name == "a:b:c"
  end

  test "parse_uri treats a colon-free label as the account name with an empty issuer" do
    assert {:ok, config} = OTPAuth.parse_uri("otpauth://totp/alice?secret=#{@secret_sha1}")
    assert config.issuer == ""
    assert config.account_name == "alice"
  end

  test "parse_uri prefers the issuer query parameter when the label has no issuer" do
    assert {:ok, config} =
             OTPAuth.parse_uri("otpauth://totp/alice?secret=#{@secret_sha1}&issuer=Acme")

    assert config.issuer == "Acme"
    assert config.account_name == "alice"
  end

  test "parse_uri normalizes the secret" do
    assert {:ok, config} =
             OTPAuth.parse_uri(
               "otpauth://totp/Acme:alice?secret=#{String.downcase(@secret_sha1)}%3D%3D"
             )

    assert config.secret == @secret_sha1
    assert OTPAuth.generate_code(config, 59) == "287082"
  end

  test "a parsed config generates codes directly" do
    uri =
      "otpauth://totp/Acme:alice?secret=#{@secret_sha512}&algorithm=SHA512&digits=8&period=30"

    assert {:ok, config} = OTPAuth.parse_uri(uri)
    assert OTPAuth.generate_code(config, 59) == "90693936"
  end

  # -------------------------------------------------------------------
  # parse_uri/1 — error semantics
  # -------------------------------------------------------------------

  test "parse_uri rejects a bad scheme" do
    assert OTPAuth.parse_uri("https://totp/Acme:alice?secret=#{@secret_sha1}") ==
             {:error, :invalid_scheme}
  end

  test "parse_uri rejects a non-totp type" do
    assert OTPAuth.parse_uri("otpauth://hotp/Acme:alice?secret=#{@secret_sha1}") ==
             {:error, :unsupported_type}
  end

  test "parse_uri rejects a missing or empty label" do
    assert OTPAuth.parse_uri("otpauth://totp/?secret=#{@secret_sha1}") ==
             {:error, :invalid_label}

    assert OTPAuth.parse_uri("otpauth://totp?secret=#{@secret_sha1}") ==
             {:error, :invalid_label}
  end

  test "parse_uri rejects a missing secret" do
    assert OTPAuth.parse_uri("otpauth://totp/Acme:alice") == {:error, :missing_secret}
    assert OTPAuth.parse_uri("otpauth://totp/Acme:alice?issuer=Acme") == {:error, :missing_secret}
  end

  test "parse_uri rejects an undecodable secret" do
    assert OTPAuth.parse_uri("otpauth://totp/Acme:alice?secret=nope!!!") ==
             {:error, :invalid_secret}
  end

  test "parse_uri rejects a label issuer that contradicts the issuer parameter" do
    assert OTPAuth.parse_uri("otpauth://totp/Acme:alice?secret=#{@secret_sha1}&issuer=Other") ==
             {:error, :issuer_mismatch}
  end

  test "parse_uri accepts a label issuer that agrees with the issuer parameter" do
    assert {:ok, config} =
             OTPAuth.parse_uri("otpauth://totp/Acme:alice?secret=#{@secret_sha1}&issuer=Acme")

    assert config.issuer == "Acme"
  end

  test "parse_uri rejects an unsupported algorithm" do
    assert OTPAuth.parse_uri("otpauth://totp/Acme:alice?secret=#{@secret_sha1}&algorithm=MD5") ==
             {:error, :unsupported_algorithm}
  end

  test "parse_uri rejects bad digit counts" do
    for digits <- ["5", "9", "six", "6.0", ""] do
      assert OTPAuth.parse_uri(
               "otpauth://totp/Acme:alice?secret=#{@secret_sha1}&digits=#{digits}"
             ) == {:error, :invalid_digits}
    end
  end

  test "parse_uri rejects bad periods" do
    for period <- ["0", "-30", "abc", "30s", ""] do
      assert OTPAuth.parse_uri(
               "otpauth://totp/Acme:alice?secret=#{@secret_sha1}&period=#{period}"
             ) == {:error, :invalid_period}
    end
  end

  test "parse_uri checks the scheme before anything else" do
    assert OTPAuth.parse_uri("ftp://hotp/?digits=9") == {:error, :invalid_scheme}
  end

  test "parse_uri checks the secret before the algorithm, digits and period" do
    assert OTPAuth.parse_uri("otpauth://totp/Acme:alice?algorithm=MD5&digits=9&period=0") ==
             {:error, :missing_secret}
  end

  test "parse_uri never raises on garbage input" do
    for junk <- ["", "://", "otpauth://", "not a uri at all", "otpauth:///?secret=A"] do
      assert {:error, reason} = OTPAuth.parse_uri(junk)
      assert is_atom(reason)
    end
  end

  # -------------------------------------------------------------------
  # round trip
  # -------------------------------------------------------------------

  test "parse_uri(build_uri(config)) round-trips a full config" do
    config = %{
      secret: @secret_sha256,
      issuer: "My Company, LLC",
      account_name: "user+tag@domain.io",
      algorithm: :sha256,
      digits: 8,
      period: 45
    }

    assert {:ok, ^config} = config |> OTPAuth.build_uri() |> OTPAuth.parse_uri()
  end

  test "round-tripping a minimal config yields the materialized defaults" do
    uri =
      OTPAuth.build_uri(%{secret: @secret_sha1, issuer: "Acme", account_name: "alice"})

    assert {:ok, config} = OTPAuth.parse_uri(uri)

    assert config == %{
             secret: @secret_sha1,
             issuer: "Acme",
             account_name: "alice",
             algorithm: :sha1,
             digits: 6,
             period: 30
           }
  end

  test "a round-tripped config generates the same codes" do
    original = %{
      secret: OTPAuth.generate_secret(),
      issuer: "Acme",
      account_name: "alice",
      algorithm: :sha512,
      digits: 7,
      period: 20
    }

    assert {:ok, parsed} = original |> OTPAuth.build_uri() |> OTPAuth.parse_uri()

    for t <- [0, 59, 1_111_111_111, 2_000_000_000] do
      assert OTPAuth.generate_code(parsed, t) == OTPAuth.generate_code(original, t)
    end
  end
end
