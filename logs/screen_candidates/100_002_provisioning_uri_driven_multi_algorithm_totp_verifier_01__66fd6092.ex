defmodule AuthenticatorURI do
  @moduledoc """
  Parses `otpauth://totp/...` provisioning URIs into validated configurations and
  generates/verifies TOTP codes from them.

  This module goes the opposite direction from a typical TOTP generator: rather than
  *building* a provisioning URI, it *consumes* one. An authenticator app must honour
  whatever the server encoded in the QR code — SHA1/SHA256/SHA512, 6/7/8 digits, and
  periods other than the customary 30 seconds — so every OTP parameter is taken from
  the URI instead of a hard-coded constant.

  The implementation relies only on the OTP standard library (`:crypto`) and includes
  its own RFC 4648 base32 decoder.

  ## Example

      iex> {:ok, config} = AuthenticatorURI.parse("otpauth://totp/ACME:alice?secret=JBSWY3DPEHPK3PXP")
      iex> config.algorithm
      :sha1
      iex> config.digits
      6
      iex> AuthenticatorURI.code_at(config, 59)
      "282760"

  """

  @type algorithm :: :sha1 | :sha256 | :sha512

  @type config :: %{
          issuer: String.t() | nil,
          account: String.t(),
          secret: String.t(),
          algorithm: algorithm(),
          digits: 6 | 7 | 8,
          period: pos_integer()
        }

  @type error ::
          :invalid_scheme
          | :unsupported_type
          | :missing_label
          | :missing_secret
          | :invalid_secret
          | :issuer_mismatch
          | :unsupported_algorithm
          | :invalid_digits
          | :invalid_period

  @base32_alphabet ~c"ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"

  @doc """
  Parses an `otpauth://totp/...` provisioning URI into a validated configuration map.

  Returns `{:ok, config}` on success, or `{:error, reason}` where `reason` is one of
  `:invalid_scheme`, `:unsupported_type`, `:missing_label`, `:missing_secret`,
  `:invalid_secret`, `:issuer_mismatch`, `:unsupported_algorithm`, `:invalid_digits`
  or `:invalid_period`.

  Defaults follow the Key Uri Format: `SHA1`, 6 digits, and a 30 second period.
  """
  @spec parse(term()) :: {:ok, config()} :: {:error, error()}
  @spec parse(term()) :: {:ok, config()} | {:error, error()}
  def parse(uri) when is_binary(uri) do
    parsed = URI.parse(uri)

    with :ok <- validate_scheme(parsed.scheme),
         :ok <- validate_type(parsed.host),
         {:ok, label_issuer, account} <- parse_label(parsed.path),
         params = URI.decode_query(parsed.query || ""),
         {:ok, secret} <- parse_secret(params),
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

  def parse(_uri), do: {:error, :invalid_scheme}

  @doc """
  Returns the OTP code for `config` at the given UNIX timestamp, in seconds.

  The code is a zero-padded decimal string of exactly `config.digits` characters,
  computed per RFC 6238 (time step) and RFC 4226 (dynamic truncation).
  """
  @spec code_at(config(), integer()) :: String.t()
  def code_at(%{period: period, digits: digits} = config, unix_time)
      when is_integer(unix_time) do
    step = div(unix_time, period)
    counter = <<step::unsigned-big-integer-size(64)>>
    key = base32_decode(config.secret)
    hmac = :crypto.mac(:hmac, hash_for(config.algorithm), key, counter)

    hmac
    |> dynamic_truncate()
    |> rem(pow10(digits))
    |> Integer.to_string()
    |> String.pad_leading(digits, "0")
  end

  @doc """
  Returns how many seconds the code current at `unix_time` remains valid.

  This is `config.period - rem(unix_time, config.period)`, so on an exact period
  boundary the full period is returned.
  """
  @spec seconds_remaining(config(), integer()) :: pos_integer()
  def seconds_remaining(%{period: period}, unix_time) when is_integer(unix_time) do
    period - rem(unix_time, period)
  end

  @doc """
  Returns `true` when `code` matches the code for the exact step containing `unix_time`.

  There is no drift window: codes from the previous or next step are rejected. `code`
  may be a string or an integer; it is zero-padded on the left to `config.digits`
  characters before being compared in constant time against `code_at/2`.
  """
  @spec verify(config(), String.t() | integer(), integer()) :: boolean()
  def verify(%{digits: digits} = config, code, unix_time) when is_integer(unix_time) do
    candidate =
      code
      |> to_string()
      |> String.pad_leading(digits, "0")

    constant_time_equal?(candidate, code_at(config, unix_time))
  end

  # -- Parsing helpers -------------------------------------------------------------

  @spec validate_scheme(String.t() | nil) :: :ok | {:error, error()}
  defp validate_scheme(scheme) when is_binary(scheme) do
    if String.downcase(scheme) == "otpauth", do: :ok, else: {:error, :invalid_scheme}
  end

  defp validate_scheme(_scheme), do: {:error, :invalid_scheme}

  @spec validate_type(String.t() | nil) :: :ok | {:error, error()}
  defp validate_type(host) when is_binary(host) do
    if String.downcase(host) == "totp", do: :ok, else: {:error, :unsupported_type}
  end

  defp validate_type(_host), do: {:error, :unsupported_type}

  @spec parse_label(String.t() | nil) ::
          {:ok, String.t() | nil, String.t()} | {:error, error()}
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

  # A single optional space directly after the colon is permitted by the spec.
  @spec strip_leading_space(String.t()) :: String.t()
  defp strip_leading_space(" " <> rest), do: rest
  defp strip_leading_space(account), do: account

  @spec parse_secret(map()) :: {:ok, String.t()} | {:error, error()}
  defp parse_secret(%{"secret" => raw}) when is_binary(raw) do
    normalized =
      raw
      |> String.replace(~r/[\s=]/u, "")
      |> String.upcase()

    if normalized != "" and valid_base32?(normalized) do
      {:ok, normalized}
    else
      {:error, :invalid_secret}
    end
  end

  defp parse_secret(_params), do: {:error, :missing_secret}

  @spec valid_base32?(String.t()) :: boolean()
  defp valid_base32?(secret) do
    secret
    |> String.to_charlist()
    |> Enum.all?(&(&1 in @base32_alphabet))
  end

  @spec parse_issuer(String.t() | nil, map()) :: {:ok, String.t() | nil} | {:error, error()}
  defp parse_issuer(label_issuer, params) do
    case {label_issuer, Map.get(params, "issuer")} do
      {nil, nil} -> {:ok, nil}
      {nil, param} -> {:ok, param}
      {label, nil} -> {:ok, label}
      {same, same} -> {:ok, same}
      {_label, _param} -> {:error, :issuer_mismatch}
    end
  end

  @spec parse_algorithm(map()) :: {:ok, algorithm()} | {:error, error()}
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

  @spec parse_digits(map()) :: {:ok, 6 | 7 | 8} | {:error, error()}
  defp parse_digits(params) do
    case Map.get(params, "digits", "6") do
      "6" -> {:ok, 6}
      "7" -> {:ok, 7}
      "8" -> {:ok, 8}
      _other -> {:error, :invalid_digits}
    end
  end

  @spec parse_period(map()) :: {:ok, pos_integer()} | {:error, error()}
  defp parse_period(params) do
    case Integer.parse(Map.get(params, "period", "30")) do
      {period, ""} when period > 0 -> {:ok, period}
      _other -> {:error, :invalid_period}
    end
  end

  # -- OTP helpers -----------------------------------------------------------------

  @spec hash_for(algorithm()) :: :sha | :sha256 | :sha512
  defp hash_for(:sha1), do: :sha
  defp hash_for(:sha256), do: :sha256
  defp hash_for(:sha512), do: :sha512

  @spec dynamic_truncate(binary()) :: non_neg_integer()
  defp dynamic_truncate(hmac) do
    offset = :binary.last(hmac) &&& 0x0F
    <<_skip::binary-size(offset), first, rest::binary-size(3), _tail::binary>> = hmac
    <<value::unsigned-big-integer-size(32)>> = <<first &&& 0x7F, rest::binary>>
    value
  end

  @spec pow10(pos_integer()) :: pos_integer()
  defp pow10(exponent), do: Integer.pow(10, exponent)

  @spec constant_time_equal?(binary(), binary()) :: boolean()
  defp constant_time_equal?(left, right)
       when byte_size(left) == byte_size(right) do
    left
    |> :binary.bin_to_list()
    |> Enum.zip(:binary.bin_to_list(right))
    |> Enum.reduce(0, fn {a, b}, acc -> Bitwise.bor(acc, Bitwise.bxor(a, b)) end)
    |> Kernel.==(0)
  end

  defp constant_time_equal?(_left, _right), do: false

  # -- RFC 4648 base32 decoding ----------------------------------------------------

  @spec base32_decode(String.t()) :: binary()
  defp base32_decode(secret) do
    bits =
      secret
      |> String.to_charlist()
      |> Enum.reduce(<<>>, fn char, acc ->
        <<acc::bitstring, base32_value(char)::size(5)>>
      end)

    # Leftover bits that do not complete a byte are discarded.
    usable = div(bit_size(bits), 8) * 8
    <<bytes::binary-size(div(usable, 8)), _rest::bitstring>> = bits
    bytes
  end

  @spec base32_value(char()) :: 0..31
  defp base32_value(char) when char >= ?A and char <= ?Z, do: char - ?A
  defp base32_value(char) when char >= ?2 and char <= ?7, do: char - ?2 + 26
end