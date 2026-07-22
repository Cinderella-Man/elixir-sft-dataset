defmodule HOTPTest do
  use ExUnit.Case, async: false

  # RFC 4226 Appendix D canonical seed, base32-encoded (unpadded) for input.
  # Base.encode32/2 is the standard-library RFC 4648 encoder, used here only to
  # build test inputs — the module implements its own base32.
  @secret Base.encode32("12345678901234567890", padding: false)

  @rfc_codes %{
    0 => "755224",
    1 => "287082",
    2 => "359152",
    3 => "969429",
    4 => "338314",
    5 => "254676",
    6 => "287922",
    7 => "162583",
    8 => "399871",
    9 => "520489"
  }

  # -------------------------------------------------------------------
  # generate_secret/0
  # -------------------------------------------------------------------

  test "generate_secret returns a 32-character base32 string" do
    secret = HOTP.generate_secret()
    assert is_binary(secret)
    assert byte_size(secret) == 32
    assert Regex.match?(~r/\A[A-Z2-7]+\z/, secret)
  end

  test "generate_secret returns different secrets each call" do
    secrets = for _ <- 1..20, do: HOTP.generate_secret()
    assert Enum.uniq(secrets) == secrets
  end

  # -------------------------------------------------------------------
  # generate_code/2 — RFC 4226 vectors and format
  # -------------------------------------------------------------------

  test "generate_code reproduces the RFC 4226 Appendix D vectors" do
    for {counter, expected} <- @rfc_codes do
      assert HOTP.generate_code(@secret, counter) == expected,
             "counter #{counter} should be #{expected}"
    end
  end

  test "generate_code returns a 6-character numeric string" do
    secret = HOTP.generate_secret()
    code = HOTP.generate_code(secret, 42)
    assert byte_size(code) == 6
    assert Regex.match?(~r/\A\d{6}\z/, code)
  end

  test "generate_code is deterministic for a given counter" do
    secret = HOTP.generate_secret()
    assert HOTP.generate_code(secret, 7) == HOTP.generate_code(secret, 7)
  end

  test "adjacent counters produce different codes" do
    refute HOTP.generate_code(@secret, 0) == HOTP.generate_code(@secret, 1)
  end

  # -------------------------------------------------------------------
  # valid?/4 — exact match and counter advance
  # -------------------------------------------------------------------

  test "valid? accepts the exact code and returns the next counter" do
    assert HOTP.valid?(@secret, "287082", 1) == {:ok, 2}
  end

  test "valid? accepts an integer code" do
    assert HOTP.valid?(@secret, 287_082, 1) == {:ok, 2}
  end

  test "valid? rejects a wrong code" do
    assert HOTP.valid?(@secret, "000000", 1) == :error
  end

  test "valid? with default look_ahead does not accept a future counter's code" do
    # "359152" is the code for counter 2, but we are at counter 1 with no look-ahead.
    assert HOTP.valid?(@secret, "359152", 1) == :error
  end

  # -------------------------------------------------------------------
  # valid?/4 — resynchronization (forward-only look-ahead)
  # -------------------------------------------------------------------

  test "valid? resynchronizes forward within the look-ahead window" do
    # Code for counter 2, server stored counter 1, look-ahead of 2 covers 1..3.
    assert HOTP.valid?(@secret, "359152", 1, look_ahead: 2) == {:ok, 3}
  end

  test "valid? rejects a code beyond the look-ahead window" do
    # Code for counter 4, server at counter 1, look-ahead 2 covers only 1..3.
    assert HOTP.valid?(@secret, "338314", 1, look_ahead: 2) == :error
  end

  test "valid? is forward-only and never checks counters below the stored one" do
    # "755224" is the code for counter 0, but the server is at counter 1;
    # even a generous look-ahead only scans forward.
    assert HOTP.valid?(@secret, "755224", 1, look_ahead: 5) == :error
  end

  test "valid? returns the counter after the matched one" do
    # Code for counter 3, stored counter 1, look-ahead 5 covers 1..6 -> match at 3.
    assert HOTP.valid?(@secret, "969429", 1, look_ahead: 5) == {:ok, 4}
  end

  # -------------------------------------------------------------------
  # provisioning_uri/4
  # -------------------------------------------------------------------

  test "provisioning_uri uses the hotp type and includes the counter" do
    uri = HOTP.provisioning_uri(@secret, "Acme", "alice@example.com", 5)
    assert String.starts_with?(uri, "otpauth://hotp/")

    parsed = URI.parse(uri)
    assert parsed.scheme == "otpauth"
    assert parsed.host == "hotp"

    params = URI.decode_query(parsed.query)
    assert params["secret"] == @secret
    assert params["issuer"] == "Acme"
    assert params["algorithm"] == "SHA1"
    assert params["digits"] == "6"
    assert params["counter"] == "5"
  end

  test "provisioning_uri encodes special characters in the label" do
    uri = HOTP.provisioning_uri(@secret, "Acme Co", "user+tag@domain.io", 0)
    assert uri =~ "Acme%20Co:user%2Btag%40domain.io"
    params = URI.decode_query(URI.parse(uri).query)
    assert params["counter"] == "0"
  end

  test "valid? returns the lowest matching counter when a code collides in the window" do
    # Scan a fixed range for two counters that produce the same code, then submit
    # that code with a window wide enough to cover both.
    result =
      Enum.reduce_while(0..20_000, %{}, fn c, seen ->
        code = HOTP.generate_code(@secret, c)

        case Map.fetch(seen, code) do
          {:ok, prev} -> {:halt, {prev, c, code}}
          :error -> {:cont, Map.put(seen, code, c)}
        end
      end)

    assert {low, high, code} = result
    assert low < high
    assert HOTP.valid?(@secret, code, low, look_ahead: high - low) == {:ok, low + 1}
  end

  test "valid? left-pads short codes before comparing them" do
    counter =
      Enum.find(0..20_000, fn c ->
        String.starts_with?(HOTP.generate_code(@secret, c), "0")
      end)

    assert is_integer(counter)
    code = HOTP.generate_code(@secret, counter)
    unpadded = String.trim_leading(code, "0")

    assert byte_size(unpadded) < 6
    assert HOTP.valid?(@secret, String.to_integer(code), counter) == {:ok, counter + 1}
    assert HOTP.valid?(@secret, unpadded, counter) == {:ok, counter + 1}
  end

  test "generate_code zero-pads codes whose numeric value has fewer than six digits" do
    counter =
      Enum.find(0..20_000, fn c ->
        String.starts_with?(HOTP.generate_code(@secret, c), "0")
      end)

    assert is_integer(counter)
    code = HOTP.generate_code(@secret, counter)

    assert byte_size(code) == 6
    assert String.starts_with?(code, "0")
    assert String.to_integer(code) < 100_000
  end

  test "valid? accepts a code at exactly counter plus look_ahead" do
    # Code for counter 3, stored counter 1, look-ahead 2 -> upper edge of 1..3.
    assert HOTP.valid?(@secret, "969429", 1, look_ahead: 2) == {:ok, 4}
  end

  test "valid? rejects a replay of an accepted code once the returned counter is stored" do
    assert {:ok, next} = HOTP.valid?(@secret, "287082", 1)
    assert next == 2
    assert HOTP.valid?(@secret, "287082", next) == :error
    assert HOTP.valid?(@secret, "287082", next, look_ahead: 5) == :error
  end
end
