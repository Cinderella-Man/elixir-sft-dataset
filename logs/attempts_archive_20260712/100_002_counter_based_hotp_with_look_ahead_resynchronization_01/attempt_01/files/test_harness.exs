defmodule HOTPTest do
  use ExUnit.Case, async: false

  # Canonical RFC 4226 secret "12345678901234567890", base32-encoded.
  @secret "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"

  # RFC 4226 Appendix D test vectors (6-digit HOTP).
  @vectors [
    {0, "755224"},
    {1, "287082"},
    {2, "359152"},
    {3, "969429"},
    {4, "338314"},
    {5, "254676"},
    {6, "287922"},
    {7, "162583"},
    {8, "399871"},
    {9, "520489"}
  ]

  # -------------------------------------------------------------------
  # generate_secret/0
  # -------------------------------------------------------------------

  test "generate_secret returns a non-empty base32 string" do
    secret = HOTP.generate_secret()
    assert is_binary(secret)
    assert byte_size(secret) > 0
    assert String.match?(secret, ~r/\A[A-Z2-7]+\z/)
  end

  test "generate_secret returns different secrets each call" do
    secrets = for _ <- 1..20, do: HOTP.generate_secret()
    assert Enum.uniq(secrets) == secrets
  end

  test "generate_secret output is decodable back into a usable key" do
    secret = HOTP.generate_secret()
    # If the base32 were malformed, generate_code would crash on decode.
    assert is_binary(HOTP.generate_code(secret, 0))
  end

  # -------------------------------------------------------------------
  # generate_code/2 — format and RFC 4226 vectors
  # -------------------------------------------------------------------

  test "generate_code returns an exactly-6-digit string" do
    code = HOTP.generate_code(@secret, 0)
    assert is_binary(code)
    assert byte_size(code) == 6
    assert String.match?(code, ~r/\A\d{6}\z/)
  end

  for {counter, expected} <- @vectors do
    test "RFC 4226 vector at counter=#{counter} produces #{expected}" do
      assert HOTP.generate_code(@secret, unquote(counter)) == unquote(expected)
    end
  end

  # -------------------------------------------------------------------
  # verify/4 — exact match and next-counter return
  # -------------------------------------------------------------------

  test "verify accepts the exact counter and returns the next counter" do
    # Counter 5 -> "254676".
    assert HOTP.verify(@secret, "254676", 5) == {:ok, 6}
  end

  test "verify accepts an integer code" do
    assert HOTP.verify(@secret, 254_676, 5) == {:ok, 6}
  end

  test "verify rejects a wrong code" do
    assert HOTP.verify(@secret, "000000", 5) == :error
  end

  # -------------------------------------------------------------------
  # verify/4 — forward look-ahead resynchronization
  # -------------------------------------------------------------------

  test "verify resynchronizes to a later counter within the look-ahead window" do
    # Counter 7 -> "162583"; from counter 5 with look_ahead 3 the window is 5..8.
    assert HOTP.verify(@secret, "162583", 5, look_ahead: 3) == {:ok, 8}
  end

  test "verify rejects a code beyond the look-ahead window" do
    # Counter 9 -> "520489"; from counter 5 with look_ahead 3 the window is 5..8.
    assert HOTP.verify(@secret, "520489", 5, look_ahead: 3) == :error
  end

  test "verify defaults look_ahead to 3" do
    # Counter 7 (in default window 5..8) resynchronizes...
    assert HOTP.verify(@secret, "162583", 5) == {:ok, 8}
    # ...but counter 9 (outside 5..8) does not.
    assert HOTP.verify(@secret, "520489", 5) == :error
  end

  test "verify with look_ahead 0 only accepts the exact counter" do
    # Counter 5 -> "254676" accepted; counter 6 -> "287922" rejected.
    assert HOTP.verify(@secret, "254676", 5, look_ahead: 0) == {:ok, 6}
    assert HOTP.verify(@secret, "287922", 5, look_ahead: 0) == :error
  end

  test "verify is forward-only and never checks earlier counters" do
    # Counter 2 -> "359152" is below the starting counter 5, so it must not match.
    assert HOTP.verify(@secret, "359152", 5, look_ahead: 3) == :error
  end

  # -------------------------------------------------------------------
  # provisioning_uri/4
  # -------------------------------------------------------------------

  test "provisioning_uri uses the otpauth hotp scheme and host" do
    uri = HOTP.provisioning_uri(@secret, "Acme", "alice@example.com", 7)
    assert String.starts_with?(uri, "otpauth://hotp/")
    parsed = URI.parse(uri)
    assert parsed.scheme == "otpauth"
    assert parsed.host == "hotp"
    assert parsed.query != nil
  end

  test "provisioning_uri encodes the label" do
    uri = HOTP.provisioning_uri(@secret, "Acme", "alice@example.com", 7)
    assert uri =~ "Acme:alice%40example.com"
  end

  test "provisioning_uri contains all required query parameters" do
    uri = HOTP.provisioning_uri(@secret, "Acme", "alice@example.com", 7)
    params = URI.decode_query(URI.parse(uri).query)
    assert params["secret"] == @secret
    assert params["issuer"] == "Acme"
    assert params["algorithm"] == "SHA1"
    assert params["digits"] == "6"
    assert params["counter"] == "7"
  end
end
