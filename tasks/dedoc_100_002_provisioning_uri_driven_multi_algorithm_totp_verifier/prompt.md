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
defmodule AuthenticatorURI do
  @base32_alphabet ~c"ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"

  def parse(uri) when is_binary(uri) do
    parsed = URI.parse(uri)

    with :ok <- validate_scheme(parsed.scheme),
         :ok <- validate_type(parsed.host),
         {:ok, label_issuer, account} <- parse_label(parsed.path) do
      params = URI.decode_query(parsed.query || "")

      with {:ok, secret} <- parse_secret(params),
           {:ok, issuer} <- parse_issuer(label_issuer, params),
           {:ok, algorithm} <- parse_algorithm(params),
           {:ok, digits} <- parse_digits(params),
           {:ok, period} <- parse_period(params) do
        {:ok,
         %{
           issuer: issuer,
           account: account,
           secret: secret,
           algorithm: algorithm,
           digits: digits,
           period: period
         }}
      end
    end
  end

  def parse(_uri), do: {:error, :invalid_scheme}

  def code_at(config, unix_time) when is_integer(unix_time) do
    step = div(unix_time, config.period)
    counter = <<step::unsigned-big-integer-size(64)>>
    key = base32_decode(config.secret)
    hmac = :crypto.mac(:hmac, hash_for(config.algorithm), key, counter)

    offset = rem(:binary.last(hmac), 16)

    <<_high_bit::size(1), truncated::unsigned-big-integer-size(31)>> =
      :binary.part(hmac, offset, 4)

    truncated
    |> rem(Integer.pow(10, config.digits))
    |> Integer.to_string()
    |> String.pad_leading(config.digits, "0")
  end

  def seconds_remaining(config, unix_time) when is_integer(unix_time) do
    config.period - rem(unix_time, config.period)
  end

  def verify(config, code, unix_time) when is_integer(unix_time) do
    candidate =
      code
      |> to_string()
      |> String.pad_leading(config.digits, "0")

    constant_time_equal?(candidate, code_at(config, unix_time))
  end

  def base32_decode(string) do
    string
    |> String.to_charlist()
    |> Enum.reduce(<<>>, fn char, acc ->
      <<acc::bitstring, base32_value(char)::size(5)>>
    end)
    |> whole_bytes(<<>>)
  end

  # -- URI component validation ---------------------------------------------------------

  defp validate_scheme(scheme) when is_binary(scheme) do
    if String.downcase(scheme) == "otpauth", do: :ok, else: {:error, :invalid_scheme}
  end

  defp validate_scheme(_scheme), do: {:error, :invalid_scheme}

  defp validate_type(host) when is_binary(host) do
    if String.downcase(host) == "totp", do: :ok, else: {:error, :unsupported_type}
  end

  defp validate_type(_host), do: {:error, :unsupported_type}

  defp parse_label(path) when is_binary(path) do
    label =
      path
      |> String.replace_prefix("/", "")
      |> URI.decode()

    case String.split(label, ":", parts: 2) do
      [""] ->
        {:error, :missing_label}

      [account] ->
        {:ok, nil, account}

      [issuer, account] ->
        issuer = String.trim(issuer)
        account = strip_leading_space(account)

        if issuer == "" or account == "" do
          {:error, :missing_label}
        else
          {:ok, issuer, account}
        end
    end
  end

  defp parse_label(_path), do: {:error, :missing_label}

  defp strip_leading_space(" " <> rest), do: rest
  defp strip_leading_space(account), do: account

  defp parse_secret(params) do
    case Map.fetch(params, "secret") do
      :error ->
        {:error, :missing_secret}

      {:ok, raw} ->
        normalized =
          raw
          |> String.replace(~r/[\s=]/u, "")
          |> String.upcase()

        cond do
          normalized == "" -> {:error, :invalid_secret}
          base32?(normalized) -> {:ok, normalized}
          true -> {:error, :invalid_secret}
        end
    end
  end

  defp base32?(string) do
    string
    |> String.to_charlist()
    |> Enum.all?(&(&1 in @base32_alphabet))
  end

  defp parse_issuer(label_issuer, params) do
    case {label_issuer, Map.get(params, "issuer")} do
      {nil, nil} -> {:ok, nil}
      {nil, param} -> {:ok, param}
      {label, nil} -> {:ok, label}
      {same, same} -> {:ok, same}
      {_label, _param} -> {:error, :issuer_mismatch}
    end
  end

  defp parse_algorithm(params) do
    params
    |> Map.get("algorithm", "SHA1")
    |> String.upcase()
    |> case do
      "SHA1" -> {:ok, :sha1}
      "SHA256" -> {:ok, :sha256}
      "SHA512" -> {:ok, :sha512}
      _other -> {:error, :unsupported_algorithm}
    end
  end

  defp parse_digits(params) do
    case Map.get(params, "digits", "6") do
      "6" -> {:ok, 6}
      "7" -> {:ok, 7}
      "8" -> {:ok, 8}
      _other -> {:error, :invalid_digits}
    end
  end

  defp parse_period(params) do
    raw = Map.get(params, "period", "30")

    case Integer.parse(raw) do
      {period, ""} when period > 0 -> {:ok, period}
      _other -> {:error, :invalid_period}
    end
  end

  # -- OTP primitives -------------------------------------------------------------------

  defp hash_for(:sha1), do: :sha
  defp hash_for(:sha256), do: :sha256
  defp hash_for(:sha512), do: :sha512

  defp base32_value(char) when char >= ?A and char <= ?Z, do: char - ?A
  defp base32_value(char) when char >= ?2 and char <= ?7, do: char - ?2 + 26

  # Keeps every complete byte of `bits` and discards the trailing partial byte, if any.
  defp whole_bytes(<<byte, rest::bitstring>>, acc), do: whole_bytes(rest, <<acc::binary, byte>>)
  defp whole_bytes(_leftover, acc), do: acc

  defp constant_time_equal?(left, right) when byte_size(left) == byte_size(right) do
    difference =
      left
      |> :binary.bin_to_list()
      |> Enum.zip(:binary.bin_to_list(right))
      |> Enum.reduce(0, fn {a, b}, acc -> :erlang.bor(acc, :erlang.bxor(a, b)) end)

    difference == 0
  end

  defp constant_time_equal?(_left, _right), do: false
end
```
