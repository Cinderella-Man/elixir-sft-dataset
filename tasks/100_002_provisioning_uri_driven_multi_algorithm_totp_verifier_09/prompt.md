# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `validate_type` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

Write me an Elixir module called `AuthenticatorURI` that goes the *other* direction from a normal TOTP generator: instead of building an `otpauth://` provisioning URI, it **parses** one into a validated configuration and then generates/verifies codes from that configuration. Use only the OTP standard library — no external dependencies.

The point of the module is that authenticator apps must accept whatever the server put in the QR code: SHA1/SHA256/SHA512, 6/7/8 digits, and periods other than 30 seconds. So all OTP parameters come from the URI, not from hard-coded constants.

## Public API

### `AuthenticatorURI.parse(uri)`

Takes an `otpauth://totp/...` URI string and returns `{:ok, config}` or `{:error, reason}` where `reason` is an atom.

`config` is a map with exactly these keys:

- `:issuer` — `String.t()` or `nil`
- `:account` — `String.t()`
- `:secret` — `String.t()` (normalized base32, see below)
- `:algorithm` — `:sha1`, `:sha256`, or `:sha512`
- `:digits` — integer, one of `6`, `7`, `8`
- `:period` — positive integer (seconds)

Parsing rules:

- **Scheme.** The scheme must be `otpauth` (compare case-insensitively). Anything else — and any non-binary argument — returns `{:error, :invalid_scheme}`.
- **Type.** The URI host is the OTP type. It must be `totp` (case-insensitive). `hotp` or anything else returns `{:error, :unsupported_type}`.
- **Label.** The path (with its leading `/` removed) is the percent-encoded label. Decode it with `URI.decode/1`. It is either `Issuer:Account` or just `Account`. A single optional space immediately after the colon is allowed and must be stripped from the account. An empty label, an empty issuer part, or an empty account part returns `{:error, :missing_label}`.
- **Query parameters.** Decode with `URI.decode_query/1` (so `+` means space).
  - `secret` (required). Strip all whitespace and `=` padding characters, then upcase. After that it must be a non-empty string of RFC 4648 base32 characters (`A`–`Z`, `2`–`7`); the normalized string is what goes into `config.secret`. A missing `secret` returns `{:error, :missing_secret}`; a secret with any other character (or one that normalizes to the empty string) returns `{:error, :invalid_secret}`.
  - `issuer` (optional). If the label carries an issuer and the `issuer` parameter is also present, they must be equal — otherwise return `{:error, :issuer_mismatch}`. If only one of them is present, that one is the issuer. If neither is present, `config.issuer` is `nil`.
  - `algorithm` (optional, default `SHA1`). Case-insensitive; `SHA1` → `:sha1`, `SHA256` → `:sha256`, `SHA512` → `:sha512`. Anything else returns `{:error, :unsupported_algorithm}`.
  - `digits` (optional, default `6`). Must be the exact decimal string of `6`, `7`, or `8`; anything else (including non-numeric text or trailing garbage) returns `{:error, :invalid_digits}`.
  - `period` (optional, default `30`). Must be the exact decimal string of a positive integer; zero, negative, or non-numeric values return `{:error, :invalid_period}`.

### `AuthenticatorURI.code_at(config, unix_time)`

Returns the OTP code for a parsed `config` at the given UNIX timestamp (seconds), as a zero-padded string of exactly `config.digits` characters.

Algorithm (RFC 6238 / RFC 4226):

1. `step = div(unix_time, config.period)`, encoded as a big-endian unsigned 64-bit integer.
2. HMAC that counter with the base32-decoded secret using `:crypto.mac(:hmac, hash, key, counter)`, where `hash` is `:sha`, `:sha256`, or `:sha512` according to `config.algorithm`.
3. Dynamic truncation: take the low 4 bits of the **last** byte of the HMAC as an offset, read the 4 bytes at that offset, mask the top bit of the first of them with `0x7F`, and interpret them big-endian.
4. Take the result modulo `10 ^ config.digits` and zero-pad on the left to `config.digits` characters.

You must implement RFC 4648 base32 **decoding** yourself (uppercase alphabet `A`–`Z` plus `2`–`7`, no padding; leftover bits that do not complete a byte are discarded). Do not use an external library.

### `AuthenticatorURI.seconds_remaining(config, unix_time)`

Returns `config.period - rem(unix_time, config.period)` — i.e. the number of seconds the current code stays valid. On an exact period boundary this returns the full period.

### `AuthenticatorURI.verify(config, code, unix_time)`

Returns `true` if `code` matches the code for the *exact* current step, `false` otherwise. There is **no** drift window: a code from the previous or next step must be rejected. `code` may be a string or an integer; normalize it by converting to a string and zero-padding on the left to `config.digits` characters, then compare against `code_at/2` using a constant-time (non-short-circuiting) byte comparison.

Give me the complete module in a single file.

## The module with `validate_type` missing

```elixir
defmodule AuthenticatorURI do
  @moduledoc """
  Parses `otpauth://totp/...` provisioning URIs into validated configurations and
  generates/verifies TOTP codes from them.

  This module works in the opposite direction of a typical TOTP generator: rather than
  building a provisioning URI from known parameters, it consumes the URI an authenticator
  app would receive (for example, from a scanned QR code) and derives every OTP parameter
  — algorithm, digit count and period — from it.

  Only the OTP standard library is used: `:crypto` for HMAC, and a hand-rolled RFC 4648
  base32 decoder for the shared secret.

  ## Example

      iex> uri = "otpauth://totp/ACME:alice?secret=JBSWY3DPEHPK3PXP"
      iex> {:ok, config} = AuthenticatorURI.parse(uri)
      iex> config.algorithm
      :sha1

  """

  @type algorithm :: :sha1 | :sha256 | :sha512

  @type t :: %{
          issuer: String.t() | nil,
          account: String.t(),
          secret: String.t(),
          algorithm: algorithm(),
          digits: 6 | 7 | 8,
          period: pos_integer()
        }

  @base32_alphabet ~c"ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"

  @doc """
  Parses an `otpauth://totp/...` provisioning URI into a validated configuration map.

  Returns `{:ok, config}` on success, or `{:error, reason}` where `reason` is one of
  `:invalid_scheme`, `:unsupported_type`, `:missing_label`, `:missing_secret`,
  `:invalid_secret`, `:issuer_mismatch`, `:unsupported_algorithm`, `:invalid_digits` or
  `:invalid_period`.
  """
  @spec parse(term()) :: {:ok, t()} | {:error, atom()}
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

  @doc """
  Returns the OTP code for `config` at the given UNIX timestamp (in seconds).

  The code is a zero-padded decimal string of exactly `config.digits` characters, computed
  per RFC 6238 / RFC 4226 using the algorithm, digit count and period from `config`.
  """
  @spec code_at(t(), integer()) :: String.t()
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

  @doc """
  Returns the number of seconds the code current at `unix_time` remains valid.

  On an exact period boundary this returns the full period.
  """
  @spec seconds_remaining(t(), integer()) :: number()
  def seconds_remaining(config, unix_time) when is_integer(unix_time) do
    config.period - rem(unix_time, config.period)
  end

  @doc """
  Returns `true` when `code` matches the code for the exact step containing `unix_time`.

  There is no drift window: codes from the previous or next step are rejected. `code` may
  be a string or an integer; it is zero-padded on the left to `config.digits` characters
  before being compared in constant time.
  """
  @spec verify(t(), String.t() | integer(), integer()) :: boolean()
  def verify(config, code, unix_time) when is_integer(unix_time) do
    candidate =
      code
      |> to_string()
      |> String.pad_leading(config.digits, "0")

    constant_time_equal?(candidate, code_at(config, unix_time))
  end

  @doc """
  Decodes an unpadded, uppercase RFC 4648 base32 string into a binary.

  Leftover bits that do not complete a byte are discarded.
  """
  @spec base32_decode(String.t()) :: binary()
  def base32_decode(string) do
    string
    |> String.to_charlist()
    |> Enum.reduce(<<>>, fn char, acc ->
      <<acc::bitstring, base32_value(char)::size(5)>>
    end)
    |> whole_bytes(<<>>)
  end

  # -- URI component validation ---------------------------------------------------------

  @spec validate_scheme(String.t() | nil) :: :ok | {:error, :invalid_scheme}
  defp validate_scheme(scheme) when is_binary(scheme) do
    if String.downcase(scheme) == "otpauth", do: :ok, else: {:error, :invalid_scheme}
  end

  defp validate_scheme(_scheme), do: {:error, :invalid_scheme}

  defp validate_type(host) when is_binary(host) do
    # TODO
  end

  @spec parse_label(String.t() | nil) ::
          {:ok, String.t() | nil, String.t()} | {:error, :missing_label}
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

  @spec strip_leading_space(String.t()) :: String.t()
  defp strip_leading_space(" " <> rest), do: rest
  defp strip_leading_space(account), do: account

  @spec parse_secret(map()) :: {:ok, String.t()} | {:error, :missing_secret | :invalid_secret}
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

  @spec base32?(String.t()) :: boolean()
  defp base32?(string) do
    string
    |> String.to_charlist()
    |> Enum.all?(&(&1 in @base32_alphabet))
  end

  @spec parse_issuer(String.t() | nil, map()) ::
          {:ok, String.t() | nil} | {:error, :issuer_mismatch}
  defp parse_issuer(label_issuer, params) do
    case {label_issuer, Map.get(params, "issuer")} do
      {nil, nil} -> {:ok, nil}
      {nil, param} -> {:ok, param}
      {label, nil} -> {:ok, label}
      {same, same} -> {:ok, same}
      {_label, _param} -> {:error, :issuer_mismatch}
    end
  end

  @spec parse_algorithm(map()) :: {:ok, algorithm()} | {:error, :unsupported_algorithm}
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

  @spec parse_digits(map()) :: {:ok, 6 | 7 | 8} | {:error, :invalid_digits}
  defp parse_digits(params) do
    case Map.get(params, "digits", "6") do
      "6" -> {:ok, 6}
      "7" -> {:ok, 7}
      "8" -> {:ok, 8}
      _other -> {:error, :invalid_digits}
    end
  end

  @spec parse_period(map()) :: {:ok, pos_integer()} | {:error, :invalid_period}
  defp parse_period(params) do
    raw = Map.get(params, "period", "30")

    case Integer.parse(raw) do
      {period, ""} when period > 0 -> {:ok, period}
      _other -> {:error, :invalid_period}
    end
  end

  # -- OTP primitives -------------------------------------------------------------------

  @spec hash_for(algorithm()) :: :sha | :sha256 | :sha512
  defp hash_for(:sha1), do: :sha
  defp hash_for(:sha256), do: :sha256
  defp hash_for(:sha512), do: :sha512

  @spec base32_value(char()) :: 0..31
  defp base32_value(char) when char >= ?A and char <= ?Z, do: char - ?A
  defp base32_value(char) when char >= ?2 and char <= ?7, do: char - ?2 + 26

  # Keeps every complete byte of `bits` and discards the trailing partial byte, if any.
  @spec whole_bytes(bitstring(), binary()) :: binary()
  defp whole_bytes(<<byte, rest::bitstring>>, acc), do: whole_bytes(rest, <<acc::binary, byte>>)
  defp whole_bytes(_leftover, acc), do: acc

  @spec constant_time_equal?(binary(), binary()) :: boolean()
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

Give me only the complete implementation of `validate_type` (including the
`@doc`/`@spec`/`@impl` lines shown above it in the module, if any) — the
function alone, not the whole module.
