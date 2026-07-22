Implement the public `valid?/4` function.

It validates a one-time-password `code` against a stored `counter` using a
forward-only resynchronization window.

- The signature is `valid?(secret, code, counter, opts \\ [])`.
- Read the `:look_ahead` option from `opts` with `Keyword.get/3`, defaulting to
  `0`. It says how many counters **beyond** `counter` may be tried.
- Normalize the supplied `code` with the existing private `normalize_code/1`
  helper, which accepts a string or an integer and left-pads it to 6 digits.
- Walk the counters `counter, counter + 1, …, counter + look_ahead` in
  **ascending** order, generating the expected code for each one with
  `generate_code/2` and comparing it to the normalized code. Counters below
  `counter` must never be checked — the window is forward-only.
- On the first (lowest) counter `c` whose generated code matches, stop
  immediately and return `{:ok, c + 1}` — the next counter the server should
  store, so the used code cannot be replayed. Do not keep scanning after a
  match.
- If no counter in the range matches, return `:error`.
- With the default `look_ahead: 0`, only `counter` itself is checked.

A short-circuiting fold over the counter range (for example
`Enum.reduce_while/3` seeded with `:error`) expresses this cleanly.

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
    # TODO
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