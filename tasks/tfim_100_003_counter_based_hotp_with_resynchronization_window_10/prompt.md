# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule HOTP do
  @moduledoc """
  RFC 4226 HMAC-based One-Time Passwords (HOTP) — the counter-based sibling of
  TOTP.

  Each code is derived from a shared secret and a monotonically increasing
  integer counter rather than the wall clock. Because a client's counter can
  drift ahead of the server's (codes generated but never submitted), validation
  supports a *forward-only* resynchronization window via the `:look_ahead`
  option.

  The implementation relies solely on the Erlang/OTP standard library
  (`:crypto`) and includes a self-contained RFC 4648 base32 codec.
  """

  import Bitwise

  @alphabet "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"

  @decode_map @alphabet
              |> String.to_charlist()
              |> Enum.with_index()
              |> Map.new()

  @digits 6
  @modulo 1_000_000

  @doc """
  Generates a cryptographically random, base32-encoded secret.

  Produces 160 bits (20 bytes) of entropy via `:crypto.strong_rand_bytes/1`,
  encoded as an unpadded RFC 4648 base32 string of exactly 32 characters.
  """
  @spec generate_secret() :: String.t()
  def generate_secret do
    20
    |> :crypto.strong_rand_bytes()
    |> base32_encode()
  end

  @doc """
  Generates the 6-digit zero-padded HOTP code for `secret` and `counter`.

  The `counter` is encoded as a big-endian 8-byte integer, HMAC-SHA1'd with the
  base32-decoded `secret`, dynamically truncated per RFC 4226 §5.3, and reduced
  modulo 1_000_000. The same inputs always yield the same code.
  """
  @spec generate_code(String.t(), non_neg_integer()) :: String.t()
  def generate_code(secret, counter) when is_integer(counter) and counter >= 0 do
    key = base32_decode(secret)
    hmac = :crypto.mac(:hmac, :sha, key, <<counter::64>>)
    offset = :binary.at(hmac, byte_size(hmac) - 1) &&& 0x0F

    truncated =
      (:binary.at(hmac, offset) &&& 0x7F) <<< 24 |||
        :binary.at(hmac, offset + 1) <<< 16 |||
        :binary.at(hmac, offset + 2) <<< 8 |||
        :binary.at(hmac, offset + 3)

    truncated
    |> rem(@modulo)
    |> Integer.to_string()
    |> String.pad_leading(@digits, "0")
  end

  @doc """
  Validates `code` against a stored `counter` using a forward-only window.

  `code` may be a string or integer and is left-padded to 6 digits before
  comparison. The option `:look_ahead` (non-negative integer, default `0`) sets
  how many counters beyond `counter` to try. Counters `counter` through
  `counter + look_ahead` are checked in ascending order; counters below
  `counter` are never checked.

  On the first (lowest) match at counter `c`, returns `{:ok, c + 1}` — the next
  counter the server should store so the used code cannot be replayed. Returns
  `:error` if nothing in the range matches.
  """
  @spec valid?(String.t(), String.t() | integer(), non_neg_integer(), keyword()) ::
          {:ok, non_neg_integer()} | :error
  def valid?(secret, code, counter, opts \\ []) do
    look_ahead = Keyword.get(opts, :look_ahead, 0)
    normalized = normalize_code(code)

    Enum.reduce_while(counter..(counter + look_ahead), :error, fn c, _acc ->
      if generate_code(secret, c) == normalized do
        {:halt, {:ok, c + 1}}
      else
        {:cont, :error}
      end
    end)
  end

  @doc """
  Builds an `otpauth://hotp/` provisioning URI for authenticator apps.

  The label is `issuer:account_name` with both parts URI-encoded. The query
  carries `secret`, `issuer`, `algorithm=SHA1`, `digits=6`, and `counter`, all
  properly URI-encoded.
  """
  @spec provisioning_uri(String.t(), String.t(), String.t(), integer()) :: String.t()
  def provisioning_uri(secret, issuer, account_name, counter) do
    label = encode_component(issuer) <> ":" <> encode_component(account_name)

    query =
      URI.encode_query([
        {"secret", secret},
        {"issuer", issuer},
        {"algorithm", "SHA1"},
        {"digits", Integer.to_string(@digits)},
        {"counter", Integer.to_string(counter)}
      ])

    "otpauth://hotp/" <> label <> "?" <> query
  end

  # --- internal helpers ---------------------------------------------------

  @spec normalize_code(String.t() | integer()) :: String.t()
  defp normalize_code(code) when is_integer(code) do
    code |> Integer.to_string() |> String.pad_leading(@digits, "0")
  end

  defp normalize_code(code) when is_binary(code) do
    String.pad_leading(code, @digits, "0")
  end

  @spec encode_component(String.t()) :: String.t()
  defp encode_component(value), do: URI.encode(value, &URI.char_unreserved?/1)

  @spec base32_encode(binary()) :: String.t()
  defp base32_encode(bytes) do
    pad = rem(5 - rem(bit_size(bytes), 5), 5)
    padded = <<bytes::bitstring, 0::size(pad)>>

    for <<chunk::5 <- padded>>, into: "" do
      binary_part(@alphabet, chunk, 1)
    end
  end

  @spec base32_decode(String.t()) :: binary()
  defp base32_decode(string) do
    {bytes, _buffer, _bits} =
      string
      |> String.upcase()
      |> String.to_charlist()
      |> Enum.reduce({<<>>, 0, 0}, fn char, {acc, buffer, bits} ->
        buffer = buffer <<< 5 ||| Map.fetch!(@decode_map, char)
        bits = bits + 5

        if bits >= 8 do
          remaining = bits - 8
          byte = buffer >>> remaining &&& 0xFF
          {<<acc::binary, byte>>, buffer, remaining}
        else
          {acc, buffer, bits}
        end
      end)

    bytes
  end
end
```

## Test harness — implement the `# TODO` test

```elixir
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
    # TODO
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

  # -------------------------------------------------------------------
  # Left-padding normalization (codes whose 6-digit form has leading zeros)
  # -------------------------------------------------------------------

  # RFC-seed vectors with leading-zero codes: counter 44 -> "000152",
  # counter 36 -> "003784". A code supplied as the integer 152 (or the short
  # string "152") must be left-padded to "000152" before comparison.
  test "valid? left-pads a short integer code to 6 digits before comparing" do
    assert HOTP.valid?(@secret, 152, 44) == {:ok, 45}
  end

  test "valid? left-pads a short string code to 6 digits before comparing" do
    assert HOTP.valid?(@secret, "152", 44) == {:ok, 45}
  end

  test "left-padded matching composes with the forward look-ahead window" do
    # Counter 36 owns "003784"; starting from 30 with look_ahead: 10 the first
    # (lowest) match is 36, so the stored counter advances to 37.
    assert HOTP.valid?(@secret, 3784, 30, look_ahead: 10) == {:ok, 37}
  end
end
```
