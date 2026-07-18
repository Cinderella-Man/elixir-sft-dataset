# Document this module

Below is a complete, working, tested Elixir module. Its behavior is correct
and must not change — but every piece of documentation has been stripped.

Add the missing documentation and typespecs:

- a `@moduledoc` that explains what the module does and how it is used,
- a `@doc` for every public function,
- a `@spec` for every public function (add `@type`s where they make the
  specs clearer).

Do not change any behavior: every function clause, guard, and expression
must keep working exactly as it does now. Do not rename anything, do not
"improve" the code, and do not add or remove functions. Give me the
complete documented module in a single file.

## The module

```elixir
defmodule HOTP do
  import Bitwise

  @alphabet "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"

  @decode_map @alphabet
              |> String.to_charlist()
              |> Enum.with_index()
              |> Map.new()

  @digits 6
  @modulo 1_000_000

  def generate_secret do
    20
    |> :crypto.strong_rand_bytes()
    |> base32_encode()
  end

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

  defp normalize_code(code) when is_integer(code) do
    code |> Integer.to_string() |> String.pad_leading(@digits, "0")
  end

  defp normalize_code(code) when is_binary(code) do
    String.pad_leading(code, @digits, "0")
  end

  defp encode_component(value), do: URI.encode(value, &URI.char_unreserved?/1)

  defp base32_encode(bytes) do
    pad = rem(5 - rem(bit_size(bytes), 5), 5)
    padded = <<bytes::bitstring, 0::size(pad)>>

    for <<chunk::5 <- padded>>, into: "" do
      binary_part(@alphabet, chunk, 1)
    end
  end

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
