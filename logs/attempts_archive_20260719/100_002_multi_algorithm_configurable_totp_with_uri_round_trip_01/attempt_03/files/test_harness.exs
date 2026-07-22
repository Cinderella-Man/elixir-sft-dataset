defmodule MultiTOTPTest do
  use ExUnit.Case, async: false

  # RFC 6238 canonical seeds, base32-encoded (unpadded) for passing to the module.
  # Base.encode32/2 is the standard-library RFC 4648 base32 encoder and is used
  # here only to build test inputs — the module implements its own base32.
  @sha1_secret Base.encode32("12345678901234567890", padding: false)
  @sha256_secret Base.encode32("12345678901234567890123456789012", padding: false)
  @sha512_secret Base.encode32(
                   "1234567890123456789012345678901234567890123456789012345678901234",
                   padding: false
                 )

  # -------------------------------------------------------------------
  # generate_secret/1
  # -------------------------------------------------------------------

  test "generate_secret defaults to a 32-character base32 string" do
    secret = MultiTOTP.generate_secret()
    assert is_binary(secret)
    assert byte_size(secret) == 32
    assert Regex.match?(~r/\A[A-Z2-7]+\z/, secret)
  end

  test "generate_secret respects the requested byte length" do
    secret = MultiTOTP.generate_secret(32)
    # ceil(32 * 8 / 5) == 52 characters, unpadded.
    assert byte_size(secret) == 52
    assert Regex.match?(~r/\A[A-Z2-7]+\z/, secret)
  end

  test "generate_secret returns different secrets each call" do
    secrets = for _ <- 1..20, do: MultiTOTP.generate_secret()
    assert Enum.uniq(secrets) == secrets
  end

  # -------------------------------------------------------------------
  # generate_code/2 — format
  # -------------------------------------------------------------------

  test "generate_code defaults to a 6-digit string" do
    secret = MultiTOTP.generate_secret()
    code = MultiTOTP.generate_code(secret, time: 90_000)
    assert byte_size(code) == 6
    assert Regex.match?(~r/\A\d{6}\z/, code)
  end

  test "generate_code honors the digits option" do
    code = MultiTOTP.generate_code(@sha1_secret, time: 59, digits: 8)
    assert byte_size(code) == 8
    assert code == "94287082"
  end

  # -------------------------------------------------------------------
  # generate_code/2 — RFC 6238 multi-algorithm vectors
  # -------------------------------------------------------------------

  test "RFC 6238 8-digit vectors for SHA1, SHA256, and SHA512" do
    vectors = [
      {:sha1, @sha1_secret, 59, "94287082"},
      {:sha256, @sha256_secret, 59, "46119246"},
      {:sha512, @sha512_secret, 59, "90693936"},
      {:sha1, @sha1_secret, 1_111_111_109, "07081804"},
      {:sha256, @sha256_secret, 1_111_111_109, "68084774"},
      {:sha512, @sha512_secret, 1_111_111_109, "25091201"},
      {:sha1, @sha1_secret, 1_234_567_890, "89005924"},
      {:sha256, @sha256_secret, 1_234_567_890, "91819424"},
      {:sha512, @sha512_secret, 1_234_567_890, "93441116"}
    ]

    for {alg, secret, t, expected} <- vectors do
      assert MultiTOTP.generate_code(secret, time: t, algorithm: alg, digits: 8) == expected,
             "#{alg} at t=#{t} should be #{expected}"
    end
  end

  test "default 6-digit SHA1 codes equal the last 6 digits of the 8-digit vectors" do
    assert MultiTOTP.generate_code(@sha1_secret, time: 59) == "287082"
    assert MultiTOTP.generate_code(@sha1_secret, time: 1_111_111_109) == "081804"
    assert MultiTOTP.generate_code(@sha1_secret, time: 1_234_567_890) == "005924"
  end

  # -------------------------------------------------------------------
  # generate_code/2 — period option
  # -------------------------------------------------------------------

  test "generate_code is stable within a configurable period and changes at the boundary" do
    secret = MultiTOTP.generate_secret()
    code = MultiTOTP.generate_code(secret, time: 600, period: 60)

    assert MultiTOTP.generate_code(secret, time: 659, period: 60) == code
    refute MultiTOTP.generate_code(secret, time: 660, period: 60) == code
  end

  # -------------------------------------------------------------------
  # valid?/3
  # -------------------------------------------------------------------

  test "valid? accepts the code produced for the same time and parameters" do
    secret = MultiTOTP.generate_secret()
    now = 90_000
    code = MultiTOTP.generate_code(secret, time: now)
    assert MultiTOTP.valid?(secret, code, time: now)
  end

  test "valid? rejects a wrong code" do
    secret = MultiTOTP.generate_secret()
    now = 90_000

    assert MultiTOTP.valid?(secret, "000000", time: now, window: 0) == false or
             MultiTOTP.generate_code(secret, time: now) == "000000"
  end

  test "valid? accepts an integer code" do
    now = 59
    str = MultiTOTP.generate_code(@sha1_secret, time: now)
    assert MultiTOTP.valid?(@sha1_secret, String.to_integer(str), time: now)
  end

  test "valid? passes algorithm and digits through" do
    assert MultiTOTP.valid?(@sha256_secret, "46119246",
             time: 59,
             algorithm: :sha256,
             digits: 8,
             window: 0
           )

    refute MultiTOTP.valid?(@sha256_secret, "00000000",
             time: 59,
             algorithm: :sha256,
             digits: 8,
             window: 0
           )
  end

  test "valid? tolerates clock drift within the window and rejects beyond it" do
    secret = MultiTOTP.generate_secret()
    now = 90_000

    code_prev = MultiTOTP.generate_code(secret, time: now - 30)
    code_two_ago = MultiTOTP.generate_code(secret, time: now - 60)

    assert MultiTOTP.valid?(secret, code_prev, time: now, window: 1)
    refute MultiTOTP.valid?(secret, code_two_ago, time: now, window: 1)
    assert MultiTOTP.valid?(secret, code_two_ago, time: now, window: 2)
  end

  test "valid? with window 0 only accepts the exact current step" do
    secret = MultiTOTP.generate_secret()
    now = 90_000

    assert MultiTOTP.valid?(secret, MultiTOTP.generate_code(secret, time: now),
             time: now,
             window: 0
           )

    refute MultiTOTP.valid?(secret, MultiTOTP.generate_code(secret, time: now - 30),
             time: now,
             window: 0
           )
  end

  # -------------------------------------------------------------------
  # provisioning_uri/4
  # -------------------------------------------------------------------

  test "provisioning_uri defaults reflect SHA1/6/30" do
    uri = MultiTOTP.provisioning_uri(@sha1_secret, "Acme", "alice@example.com")
    assert String.starts_with?(uri, "otpauth://totp/")
    params = URI.decode_query(URI.parse(uri).query || "")
    assert params["secret"] == @sha1_secret
    assert params["issuer"] == "Acme"
    assert params["algorithm"] == "SHA1"
    assert params["digits"] == "6"
    assert params["period"] == "30"
  end

  test "provisioning_uri reflects supplied options" do
    uri =
      MultiTOTP.provisioning_uri(@sha256_secret, "Acme Co", "bob@example.com",
        algorithm: :sha256,
        digits: 8,
        period: 60
      )

    params = URI.decode_query(URI.parse(uri).query || "")
    assert params["algorithm"] == "SHA256"
    assert params["digits"] == "8"
    assert params["period"] == "60"
  end

  # -------------------------------------------------------------------
  # parse_uri/1 — inverse operation
  # -------------------------------------------------------------------

  test "parse_uri round-trips a URI built with non-default options" do
    uri =
      MultiTOTP.provisioning_uri(@sha1_secret, "Acme", "alice@example.com",
        algorithm: :sha256,
        digits: 8,
        period: 60
      )

    assert {:ok, m} = MultiTOTP.parse_uri(uri)
    assert m.secret == @sha1_secret
    assert m.issuer == "Acme"
    assert m.account_name == "alice@example.com"
    assert m.algorithm == :sha256
    assert m.digits == 8
    assert m.period == 60
  end

  test "parse_uri applies defaults for absent parameters" do
    uri = MultiTOTP.provisioning_uri(@sha1_secret, "Acme", "bob")
    assert {:ok, m} = MultiTOTP.parse_uri(uri)
    assert m.algorithm == :sha1
    assert m.digits == 6
    assert m.period == 30
    assert m.account_name == "bob"
  end

  test "parse_uri rejects a non-otpauth URI" do
    assert {:error, :invalid_uri} = MultiTOTP.parse_uri("https://example.com/foo")
  end

  test "parse_uri rejects an unsupported algorithm" do
    bad = "otpauth://totp/Acme:bob?secret=ABCDEF&algorithm=SHA3&digits=6&period=30"
    assert {:error, :unsupported_algorithm} = MultiTOTP.parse_uri(bad)
  end
end
