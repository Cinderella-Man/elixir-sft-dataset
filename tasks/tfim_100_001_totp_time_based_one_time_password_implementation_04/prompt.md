# Complete the blanked test

You get a module and its ExUnit harness, minus the body of ONE `test` —
the `# TODO` marks the spot, and its name says what it must prove. Write
exactly that test so the harness passes against a correct implementation
of the module.

## Module under test

```elixir
defmodule TOTP do
  @moduledoc """
  RFC 6238 Time-Based One-Time Password (TOTP) implementation.

  Produces 6-digit HMAC-SHA1 codes with a 30-second period, compatible with
  Google Authenticator, Authy, 1Password, and other RFC 6238 authenticators.

  Uses only Erlang/OTP and Elixir standard libraries — no external dependencies.
  """

  import Bitwise

  @period 30
  @digits 6
  @secret_bytes 20

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Generates a cryptographically random, base32-encoded 160-bit secret
  (20 bytes → 32 characters, no padding).
  """
  @spec generate_secret() :: String.t()
  def generate_secret do
    @secret_bytes
    |> :crypto.strong_rand_bytes()
    |> base32_encode()
  end

  @doc """
  Returns the 6-digit TOTP code for `secret` at the given UNIX timestamp.
  """
  @spec generate_code(String.t(), integer()) :: String.t()
  def generate_code(secret, time \\ :os.system_time(:second)) do
    key = base32_decode!(secret)
    step = div(time, @period)
    counter = <<step::big-unsigned-integer-size(64)>>

    :hmac
    |> :crypto.mac(:sha, key, counter)
    |> dynamic_truncate()
    |> rem(1_000_000)
    |> Integer.to_string()
    |> String.pad_leading(@digits, "0")
  end

  @doc """
  Validates `code` against `secret`, tolerating clock drift.

  ## Options

    * `:time`   — UNIX seconds to validate against (default: current time)
    * `:window` — number of 30-second steps accepted in each direction (default: 1)
  """
  @spec valid?(String.t(), String.t() | integer(), keyword()) :: boolean()
  def valid?(secret, code, opts \\ []) do
    time = Keyword.get(opts, :time, :os.system_time(:second))
    window = Keyword.get(opts, :window, 1)
    expected = normalize_code(code)

    Enum.any?(-window..window, fn offset ->
      t = time + offset * @period
      secure_equal?(generate_code(secret, t), expected)
    end)
  end

  @doc """
  Builds an `otpauth://totp/` provisioning URI for authenticator apps.

  The label is `issuer:account_name` (both URI-encoded); query parameters
  include `secret`, `issuer`, `algorithm=SHA1`, `digits=6`, `period=30`.
  """
  @spec provisioning_uri(String.t(), String.t(), String.t()) :: String.t()
  def provisioning_uri(secret, issuer, account_name) do
    label =
      URI.encode(issuer, &URI.char_unreserved?/1) <>
        ":" <> URI.encode(account_name, &URI.char_unreserved?/1)

    query =
      URI.encode_query([
        {"secret", secret},
        {"issuer", issuer},
        {"algorithm", "SHA1"},
        {"digits", Integer.to_string(@digits)},
        {"period", Integer.to_string(@period)}
      ])

    "otpauth://totp/" <> label <> "?" <> query
  end

  # ---------------------------------------------------------------------------
  # Dynamic truncation (RFC 4226 §5.3)
  # ---------------------------------------------------------------------------

  defp dynamic_truncate(<<_::binary-size(19), last::8>> = hmac) do
    offset = last &&& 0x0F
    <<_::binary-size(^offset), b0, b1, b2, b3, _::binary>> = hmac

    (b0 &&& 0x7F) <<< 24 ||| b1 <<< 16 ||| b2 <<< 8 ||| b3
  end

  # ---------------------------------------------------------------------------
  # Base32 (RFC 4648, uppercase A–Z + 2–7, unpadded)
  # ---------------------------------------------------------------------------

  # --- encode ---

  defp base32_encode(data) when is_binary(data), do: encode_groups(data, <<>>)

  # Consume 5 bytes (40 bits) at a time, emit 8 characters.
  defp encode_groups(
         <<a::5, b::5, c::5, d::5, e::5, f::5, g::5, h::5, rest::binary>>,
         acc
       ) do
    chunk = <<enc(a), enc(b), enc(c), enc(d), enc(e), enc(f), enc(g), enc(h)>>
    encode_groups(rest, <<acc::binary, chunk::binary>>)
  end

  defp encode_groups(<<>>, acc), do: acc

  # 1–4 byte remainder: right-pad with zero bits to a 5-bit boundary, then emit.
  defp encode_groups(rest, acc) when is_binary(rest) do
    pad = rem(5 - rem(bit_size(rest), 5), 5)
    encode_tail(<<rest::bitstring, 0::size(pad)>>, acc)
  end

  defp encode_tail(<<>>, acc), do: acc

  defp encode_tail(<<x::5, rest::bitstring>>, acc),
    do: encode_tail(rest, <<acc::binary, enc(x)>>)

  defp enc(i) when i in 0..25, do: ?A + i
  defp enc(i) when i in 26..31, do: ?2 + (i - 26)

  # --- decode ---

  defp base32_decode!(str) when is_binary(str) do
    bits = decode_bits(String.upcase(str), <<>>)
    byte_count = div(bit_size(bits), 8)
    <<bytes::binary-size(^byte_count), _::bitstring>> = bits
    bytes
  end

  defp decode_bits(<<>>, acc), do: acc

  defp decode_bits(<<c, rest::binary>>, acc),
    do: decode_bits(rest, <<acc::bitstring, dec!(c)::5>>)

  defp dec!(c) when c in ?A..?Z, do: c - ?A
  defp dec!(c) when c in ?2..?7, do: c - ?2 + 26
  defp dec!(c), do: raise(ArgumentError, "invalid base32 character: #{<<c>>}")

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp normalize_code(code) when is_integer(code),
    do: code |> Integer.to_string() |> String.pad_leading(@digits, "0")

  defp normalize_code(code) when is_binary(code),
    do: String.pad_leading(code, @digits, "0")

  # Constant-time string compare — avoids leaking match position via timing.
  defp secure_equal?(a, b) when byte_size(a) == byte_size(b) do
    a
    |> :binary.bin_to_list()
    |> Enum.zip(:binary.bin_to_list(b))
    |> Enum.reduce(0, fn {x, y}, acc -> acc ||| bxor(x, y) end)
    |> Kernel.==(0)
  end

  defp secure_equal?(_, _), do: false
end
```

## Test harness — implement the `# TODO` test

```elixir
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
    # TODO
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

  test "generate_secret encodes exactly 160 bits as 32 unpadded base32 characters" do
    for _ <- 1..10 do
      secret = TOTP.generate_secret()
      assert byte_size(secret) == 32
      refute String.contains?(secret, "=")
      assert String.match?(secret, ~r/\A[A-Z2-7]{32}\z/)
    end
  end

  test "valid? without a window option tolerates exactly one step of drift in each direction" do
    secret = TOTP.generate_secret()
    now = 90_000

    assert TOTP.valid?(secret, TOTP.generate_code(secret, now - 30), time: now)
    assert TOTP.valid?(secret, TOTP.generate_code(secret, now + 30), time: now)
    refute TOTP.valid?(secret, TOTP.generate_code(secret, now - 60), time: now)
    refute TOTP.valid?(secret, TOTP.generate_code(secret, now + 60), time: now)
  end

  test "valid? accepts an integer code whose decimal form is shorter than six digits" do
    time = 1_234_567_890
    assert TOTP.generate_code(@rfc_secret, time) == "005924"

    assert TOTP.valid?(@rfc_secret, 5924, time: time, window: 0)
    refute TOTP.valid?(@rfc_secret, 5925, time: time, window: 0)
  end

  test "provisioning_uri label decodes back to issuer colon account_name" do
    uri = TOTP.provisioning_uri(@rfc_secret, "Acme Co", "alice@example.com")
    parsed = URI.parse(uri)

    label =
      parsed.path
      |> String.trim_leading("/")
      |> URI.decode()

    assert label == "Acme Co:alice@example.com"

    params = URI.decode_query(parsed.query)
    assert params["issuer"] == "Acme Co"
    assert params["algorithm"] == "SHA1"
  end
end
```
