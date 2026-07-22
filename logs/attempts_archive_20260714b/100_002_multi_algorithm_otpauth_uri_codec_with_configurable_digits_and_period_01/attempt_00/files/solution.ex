defmodule OTPAuth do
  @moduledoc """
  A multi-algorithm, configuration-driven one-time-password codec.

  `OTPAuth` implements RFC 6238 time-based one-time passwords (TOTP) on top of the
  RFC 4226 HOTP dynamic-truncation algorithm, plus a complete `otpauth://` provisioning
  URI codec: it can both build a URI from a config map and parse a third-party URI back
  into one.

  Everything is driven by a plain map (the *config*):

    * `:secret` — base32-encoded shared secret (required)
    * `:issuer` — issuer string (required by `build_uri/1`)
    * `:account_name` — account name string (required by `build_uri/1`)
    * `:algorithm` — `:sha1` | `:sha256` | `:sha512` (default `:sha1`)
    * `:digits` — `6`, `7` or `8` (default `6`)
    * `:period` — positive integer seconds (default `30`)

  Code generation (`generate_code/2`, `valid?/3`) only requires `:secret`; the remaining
  algorithm knobs fall back to the defaults above when absent.

  Base32 encoding/decoding is implemented in this module (RFC 4648, alphabet `A`-`Z` and
  `2`-`7`, no padding on output). Decoding is deliberately lenient about *presentation* —
  lowercase input, embedded ASCII whitespace and trailing `=` padding are all tolerated,
  because authenticator apps display secrets in whitespace-separated groups.

  Parsing never raises: `parse_uri/1` returns `{:ok, config}` or `{:error, reason}`.

      iex> config = %{secret: "JBSWY3DPEHPK3PXP", issuer: "Acme", account_name: "alice"}
      iex> OTPAuth.generate_code(config, 59)
      "287082"

  """

  @default_algorithm :sha1
  @default_digits 6
  @default_period 30
  @default_secret_bytes 20

  @b32_alphabet ~c"ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"

  @type algorithm :: :sha1 | :sha256 | :sha512

  @type config :: %{
          optional(:secret) => String.t(),
          optional(:issuer) => String.t(),
          optional(:account_name) => String.t(),
          optional(:algorithm) => algorithm(),
          optional(:digits) => 6 | 7 | 8,
          optional(:period) => pos_integer()
        }

  @type parse_error ::
          :invalid_scheme
          | :unsupported_type
          | :invalid_label
          | :missing_secret
          | :invalid_secret
          | :issuer_mismatch
          | :unsupported_algorithm
          | :invalid_digits
          | :invalid_period

  @doc """
  Generates a cryptographically random base32 secret.

  `bytes` bytes of entropy are drawn from `:crypto.strong_rand_bytes/1` (default `20`,
  i.e. 160 bits, the size recommended by RFC 4226) and encoded as an unpadded, uppercase
  RFC 4648 base32 string matching `~r/\\A[A-Z2-7]+\\z/`.

  ## Examples

      iex> secret = OTPAuth.generate_secret()
      iex> String.match?(secret, ~r/\\A[A-Z2-7]+\\z/)
      true

  """
  @spec generate_secret(pos_integer()) :: String.t()
  def generate_secret(bytes \\ @default_secret_bytes) when is_integer(bytes) and bytes > 0 do
    bytes
    |> :crypto.strong_rand_bytes()
    |> base32_encode()
  end

  @doc """
  Decodes a base32 `secret` into its raw binary form.

  Returns `{:ok, binary}`, or `{:error, :invalid_secret}` when the secret contains a
  character outside the RFC 4648 base32 alphabet or carries fewer than 8 bits of data.

  Lowercase letters are upcased, ASCII whitespace is stripped, trailing `=` padding is
  ignored and trailing bits that do not complete a byte are discarded.

  ## Examples

      iex> OTPAuth.decode_secret("jbsw y3dp ====")
      {:ok, "Hello"}

      iex> OTPAuth.decode_secret("1234")
      {:error, :invalid_secret}

  """
  @spec decode_secret(String.t()) :: {:ok, binary()} | {:error, :invalid_secret}
  def decode_secret(secret) when is_binary(secret) do
    secret
    |> normalize_secret()
    |> base32_decode()
  end

  def decode_secret(_secret), do: {:error, :invalid_secret}

  @doc """
  Generates the TOTP code for `config` at the given UNIX `time` (seconds).

  The counter is `div(time, period)` encoded as a big-endian unsigned 64-bit integer, HMACed
  with the decoded secret under the configured hash algorithm, then reduced with the RFC 4226
  §5.3 dynamic-truncation rule and taken modulo `10 ** digits`. The result is zero-padded to
  exactly `digits` characters.

  Raises `ArgumentError` if `config.secret` is not valid base32.

  ## Examples

      iex> OTPAuth.generate_code(%{secret: "JBSWY3DPEHPK3PXP"}, 1_111_111_109)
      "081804"

  """
  @spec generate_code(config(), integer()) :: String.t()
  def generate_code(config, time \\ :os.system_time(:second))
      when is_map(config) and is_integer(time) do
    key =
      case decode_secret(Map.fetch!(config, :secret)) do
        {:ok, key} -> key
        {:error, :invalid_secret} -> raise ArgumentError, "invalid base32 secret"
      end

    algorithm = algorithm(config)
    digits = digits(config)
    period = period(config)

    counter = div(time, period)
    hmac = :crypto.mac(:hmac, algorithm, key, <<counter::unsigned-big-integer-size(64)>>)

    hmac
    |> dynamic_truncate()
    |> rem(pow10(digits))
    |> Integer.to_string()
    |> String.pad_leading(digits, "0")
  end

  @doc """
  Checks whether `code` is valid for `config`.

  `code` may be a string or an integer (an integer is zero-padded to `digits` first).

  ## Options

    * `:time` — UNIX seconds to validate against (default: current system time)
    * `:window` — number of `config.period` steps accepted in *each* direction (default `1`);
      `0` accepts only the current step

  The comparison against every candidate code is constant-time with respect to the length of
  a matching prefix.

  ## Examples

      iex> config = %{secret: "JBSWY3DPEHPK3PXP"}
      iex> OTPAuth.valid?(config, OTPAuth.generate_code(config, 1_000), time: 1_000, window: 0)
      true

  """
  @spec valid?(config(), String.t() | integer(), keyword()) :: boolean()
  def valid?(config, code, opts \\ []) when is_map(config) and is_list(opts) do
    digits = digits(config)
    period = period(config)
    time = Keyword.get(opts, :time, :os.system_time(:second))
    window = Keyword.get(opts, :window, 1)

    expected = normalize_code(code, digits)

    -window..window
    |> Enum.reduce(false, fn step, acc ->
      candidate = generate_code(config, time + step * period)
      secure_compare(candidate, expected) or acc
    end)
  end

  @doc """
  Builds an `otpauth://totp/` provisioning URI from `config`.

  The label is `issuer:account_name` with each side percent-encoded down to the unreserved
  character set. The query string is emitted in a fixed key order — `secret`, `issuer`,
  `algorithm`, `digits`, `period` — with defaults materialized, so a config carrying only
  `:secret`, `:issuer` and `:account_name` still emits `algorithm=SHA1`, `digits=6` and
  `period=30`.

  ## Examples

      iex> OTPAuth.build_uri(%{secret: "JBSWY3DP", issuer: "Acme", account_name: "alice"})
      "otpauth://totp/Acme:alice?secret=JBSWY3DP&issuer=Acme&algorithm=SHA1&digits=6&period=30"

  """
  @spec build_uri(config()) :: String.t()
  def build_uri(config) when is_map(config) do
    secret = Map.fetch!(config, :secret)
    issuer = Map.fetch!(config, :issuer)
    account_name = Map.fetch!(config, :account_name)

    label = encode_component(issuer) <> ":" <> encode_component(account_name)

    query =
      URI.encode_query([
        {"secret", secret},
        {"issuer", issuer},
        {"algorithm", algorithm_to_string(algorithm(config))},
        {"digits", Integer.to_string(digits(config))},
        {"period", Integer.to_string(period(config))}
      ])

    "otpauth://totp/" <> label <> "?" <> query
  end

  @doc """
  Parses an `otpauth://` provisioning URI into a config map.

  Returns `{:ok, config}` with all six keys populated (defaults filled in and the secret
  normalized — upcased, whitespace and `=` padding removed), or `{:error, reason}`. This
  function never raises, whatever the input.

  Failures are reported in a fixed precedence: `:invalid_scheme`, `:unsupported_type`,
  `:invalid_label`, `:missing_secret`, `:invalid_secret`, `:issuer_mismatch`,
  `:unsupported_algorithm`, `:invalid_digits`, `:invalid_period`.

  ## Examples

      iex> OTPAuth.parse_uri("otpauth://totp/Acme:alice?secret=JBSWY3DP&digits=8")
      {:ok,
       %{
         secret: "JBSWY3DP",
         issuer: "Acme",
         account_name: "alice",
         algorithm: :sha1,
         digits: 8,
         period: 30
       }}

      iex> OTPAuth.parse_uri("https://example.com")
      {:error, :invalid_scheme}

  """
  @spec parse_uri(String.t()) :: {:ok, map()} | {:error, parse_error()}
  def parse_uri(uri) when is_binary(uri) do
    parsed = URI.parse(uri)

    with :ok <- check_scheme(parsed),
         :ok <- check_type(parsed),
         {:ok, label_issuer, account_name} <- parse_label(parsed),
         params = decode_query(parsed),
         {:ok, secret} <- fetch_secret(params),
         {:ok, issuer} <- resolve_issuer(label_issuer, params),
         {:ok, algorithm} <- parse_algorithm(params),
         {:ok, digits} <- parse_digits(params),
         {:ok, period} <- parse_period(params) do
      {:ok,
       %{
         secret: secret,
         issuer: issuer,
         account_name: account_name,
         algorithm: algorithm,
         digits: digits,
         period: period
       }}
    end
  end

  def parse_uri(_uri), do: {:error, :invalid_scheme}

  # -- URI parsing helpers ---------------------------------------------------------------

  defp check_scheme(%URI{scheme: "otpauth"}), do: :ok
  defp check_scheme(%URI{}), do: {:error, :invalid_scheme}

  defp check_type(%URI{host: host}) when is_binary(host) do
    case String.downcase(host) do
      "totp" -> :ok
      _other -> {:error, :unsupported_type}
    end
  end

  defp check_type(%URI{}), do: {:error, :unsupported_type}

  defp parse_label(%URI{path: path}) when is_binary(path) do
    raw =
      path
      |> String.trim_leading("/")
      |> safe_decode()

    case raw do
      nil ->
        {:error, :invalid_label}

      "" ->
        {:error, :invalid_label}

      label ->
        case String.split(label, ":", parts: 2) do
          [account_name] ->
            {:ok, nil, account_name}

          [label_issuer, account_name] ->
            {:ok, label_issuer, String.trim_leading(account_name, " ")}
        end
    end
  end

  defp parse_label(%URI{}), do: {:error, :invalid_label}

  defp safe_decode(string) do
    URI.decode(string)
  rescue
    ArgumentError -> nil
  end

  defp decode_query(%URI{query: nil}), do: %{}

  defp decode_query(%URI{query: query}) do
    URI.decode_query(query)
  rescue
    ArgumentError -> %{}
  end

  defp fetch_secret(params) do
    case Map.fetch(params, "secret") do
      {:ok, raw} ->
        normalized = normalize_secret(raw)

        case base32_decode(normalized) do
          {:ok, _binary} -> {:ok, normalized}
          {:error, :invalid_secret} -> {:error, :invalid_secret}
        end

      :error ->
        {:error, :missing_secret}
    end
  end

  defp resolve_issuer(label_issuer, params) do
    query_issuer = Map.get(params, "issuer")

    cond do
      is_binary(label_issuer) and is_binary(query_issuer) and label_issuer != query_issuer ->
        {:error, :issuer_mismatch}

      is_binary(query_issuer) ->
        {:ok, query_issuer}

      is_binary(label_issuer) ->
        {:ok, label_issuer}

      true ->
        {:ok, ""}
    end
  end

  defp parse_algorithm(params) do
    case params |> Map.get("algorithm", "sha1") |> String.downcase() do
      "sha1" -> {:ok, :sha1}
      "sha256" -> {:ok, :sha256}
      "sha512" -> {:ok, :sha512}
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

  # -- Config accessors ------------------------------------------------------------------

  defp algorithm(config) do
    case Map.get(config, :algorithm) do
      nil -> @default_algorithm
      algorithm when algorithm in [:sha1, :sha256, :sha512] -> algorithm
    end
  end

  defp digits(config) do
    case Map.get(config, :digits) do
      nil -> @default_digits
      digits when digits in [6, 7, 8] -> digits
    end
  end

  defp period(config) do
    case Map.get(config, :period) do
      nil -> @default_period
      period when is_integer(period) and period > 0 -> period
    end
  end

  defp algorithm_to_string(:sha1), do: "SHA1"
  defp algorithm_to_string(:sha256), do: "SHA256"
  defp algorithm_to_string(:sha512), do: "SHA512"

  # -- OTP internals ---------------------------------------------------------------------

  defp dynamic_truncate(hmac) do
    offset = :binary.last(hmac) &&& 0x0F
    <<_skip::binary-size(offset), slice::binary-size(4), _rest::binary>> = hmac
    <<first, second, third, fourth>> = slice

    (first &&& 0x7F) <<< 24 ||| second <<< 16 ||| third <<< 8 ||| fourth
  end

  defp pow10(digits), do: Integer.pow(10, digits)

  defp normalize_code(code, digits) when is_integer(code) do
    code
    |> Integer.to_string()
    |> String.pad_leading(digits, "0")
  end

  defp normalize_code(code, _digits) when is_binary(code), do: code

  # Compares two strings without leaking, through timing, the length of a matching prefix.
  defp secure_compare(left, right) when byte_size(left) == byte_size(right) do
    :crypto.hash_equals(left, right)
  rescue
    # Older OTP releases lack :crypto.hash_equals/2 — fall back to a manual XOR fold.
    UndefinedFunctionError -> xor_compare(left, right)
  end

  defp secure_compare(_left, _right), do: false

  defp xor_compare(left, right) do
    left
    |> :binary.bin_to_list()
    |> Enum.zip(:binary.bin_to_list(right))
    |> Enum.reduce(0, fn {l, r}, acc -> acc ||| bxor(l, r) end)
    |> Kernel.===(0)
  end

  # -- Base32 (RFC 4648) -----------------------------------------------------------------

  defp normalize_secret(secret) do
    secret
    |> String.upcase()
    |> String.replace(~r/[\s=]/, "")
  end

  defp base32_encode(binary) when is_binary(binary) do
    binary
    |> encode_chunks([])
    |> Enum.reverse()
    |> List.to_string()
  end

  defp encode_chunks(<<a::5, rest::bitstring>>, acc) do
    encode_chunks(rest, [Enum.at(@b32_alphabet, a) | acc])
  end

  defp encode_chunks(<<>>, acc), do: acc

  defp encode_chunks(remainder, acc) when is_bitstring(remainder) do
    pad = 5 - bit_size(remainder)
    <<a::5>> = <<remainder::bitstring, 0::size(pad)>>
    [Enum.at(@b32_alphabet, a) | acc]
  end

  # Expects an already-normalized (upcased, whitespace/padding-free) secret.
  defp base32_decode(""), do: {:error, :invalid_secret}

  defp base32_decode(secret) do
    case decode_chars(secret, <<>>) do
      {:ok, bits} when bit_size(bits) >= 8 ->
        usable = div(bit_size(bits), 8) * 8
        <<binary::binary-size(div(usable, 8)), _leftover::bitstring>> = bits
        {:ok, binary}

      _other ->
        {:error, :invalid_secret}
    end
  end

  defp decode_chars(<<char, rest::binary>>, acc) do
    case b32_value(char) do
      nil -> {:error, :invalid_secret}
      value -> decode_chars(rest, <<acc::bitstring, value::5>>)
    end
  end

  defp decode_chars(<<>>, acc), do: {:ok, acc}

  defp b32_value(char) when char in ?A..?Z, do: char - ?A
  defp b32_value(char) when char in ?2..?7, do: char - ?2 + 26
  defp b32_value(_char), do: nil

  # -- Percent-encoding ------------------------------------------------------------------

  defp encode_component(value) do
    URI.encode(value, &URI.char_unreserved?/1)
  end

  import Bitwise
end
