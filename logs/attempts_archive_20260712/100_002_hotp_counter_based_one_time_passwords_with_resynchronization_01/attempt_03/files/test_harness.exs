defmodule HOTPTest do
  use ExUnit.Case, async: false

  # RFC 4226 Appendix D canonical secret: ASCII "12345678901234567890"
  # base32-encoded (unpadded).
  @rfc_secret "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"

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

  test "generate_secret output is usable by generate_code" do
    secret = HOTP.generate_secret()
    code = HOTP.generate_code(secret, 0)
    assert is_binary(code)
    assert byte_size(code) == 6
  end

  # -------------------------------------------------------------------
  # generate_code/2 — RFC 4226 Appendix D test vectors
  # -------------------------------------------------------------------

  for {counter, expected} <- [
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
      ] do
    test "RFC vector at counter=#{counter} produces #{expected}" do
      assert HOTP.generate_code(@rfc_secret, unquote(counter)) == unquote(expected)
    end
  end

  test "generate_code returns a 6-character numeric string" do
    code = HOTP.generate_code(@rfc_secret, 42)
    assert byte_size(code) == 6
    assert String.match?(code, ~r/\A\d{6}\z/)
  end

  # -------------------------------------------------------------------
  # valid?/4
  # -------------------------------------------------------------------

  test "valid? accepts the exact counter's code by default" do
    assert HOTP.valid?(@rfc_secret, "287082", 1)
  end

  test "valid? accepts an integer code as well as a string" do
    assert HOTP.valid?(@rfc_secret, 287_082, 1)
  end

  test "valid? rejects a code for a different counter by default" do
    refute HOTP.valid?(@rfc_secret, "287082", 2)
  end

  test "valid? with look_ahead accepts codes for counters ahead" do
    # "254676" is the code for counter 5; validating from counter 3 with
    # look_ahead 2 covers counters 3..5.
    assert HOTP.valid?(@rfc_secret, "254676", 3, look_ahead: 2)
  end

  test "valid? with look_ahead still rejects codes beyond the window" do
    # counter 6 is outside 3..5.
    refute HOTP.valid?(@rfc_secret, "287922", 3, look_ahead: 2)
  end

  # -------------------------------------------------------------------
  # verify/4 — resynchronization
  # -------------------------------------------------------------------

  test "verify returns the next counter for an exact match" do
    assert HOTP.verify(@rfc_secret, "287082", 1) == {:ok, 2}
  end

  test "verify resynchronizes to a counter ahead within the default look-ahead" do
    # Server expects counter 1, client is at counter 3 ("969429").
    # Default look_ahead is 3, so range 1..4 covers it; next stored counter is 4.
    assert HOTP.verify(@rfc_secret, "969429", 1) == {:ok, 4}
  end

  test "verify returns :error when the code is outside the look-ahead range" do
    # counter 5 ("254676") is outside 1..4 with the default look_ahead of 3.
    assert HOTP.verify(@rfc_secret, "254676", 1) == :error
  end

  test "verify respects a custom look_ahead" do
    assert HOTP.verify(@rfc_secret, "254676", 1, look_ahead: 4) == {:ok, 6}
  end

  test "verify returns :error for a completely wrong code" do
    assert HOTP.verify(@rfc_secret, "000000", 1) == :error
  end

  # -------------------------------------------------------------------
  # provisioning_uri/4
  # -------------------------------------------------------------------

  test "provisioning_uri starts with otpauth://hotp/" do
    uri = HOTP.provisioning_uri(@rfc_secret, "Acme", "alice@example.com", 0)
    assert String.starts_with?(uri, "otpauth://hotp/")
  end

  test "provisioning_uri includes the counter and required parameters" do
    uri = HOTP.provisioning_uri(@rfc_secret, "Acme", "alice@example.com", 7)
    assert uri =~ "secret=#{@rfc_secret}"
    assert uri =~ "issuer=Acme"
    assert uri =~ "algorithm=SHA1"
    assert uri =~ "digits=6"
    assert uri =~ "counter=7"
  end

  test "provisioning_uri is parseable and encodes the label" do
    uri = HOTP.provisioning_uri(@rfc_secret, "Acme Co", "alice@example.com", 0)
    parsed = URI.parse(uri)
    assert parsed.scheme == "otpauth"
    assert parsed.host == "hotp"
    assert uri =~ "Acme%20Co:alice%40example.com"
  end
end
