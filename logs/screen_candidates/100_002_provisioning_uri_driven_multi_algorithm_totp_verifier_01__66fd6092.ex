defmodule AuthenticatorURI do
  @moduledoc """
  Parse `otpauth://totp/...` provisioning URIs into a validated configuration and
  generate/verify RFC 6238 TOTP codes from that configuration.

  This module goes the *opposite* direction of a typical TOTP provisioning-URI
  builder. Instead of emitting an `otpauth://` URI from fixed parameters, it
  consumes one — the way an authenticator app scanning a QR code must — and honors
  whatever the server chose: SHA1/SHA256/SHA512, 6/7/8 digits, and any positive
  period. Every OTP parameter is taken from the URI, never from hard-coded
  constants.

  Only the OTP standard library is used (`URI`, `:crypto`, `Integer`, `Bitwise`).
  RFC 4648 base32 decoding is implemented here directly.
  """

  import Bitwise

  @type algorithm :: :sha1 | :sha256 | :sha512

  @type config :: %{
          issuer: String.t() | nil,
          account: String.t(),
          secret: String.t(),
          algorithm: algorithm(),
          digits: 6 | 7 | 8,
          period: pos_integer()
        }

  @doc """
  Parse an `otpauth://totp/...` URI into a validated configuration map.

  Returns `{:ok, config}` on success or `{:error, reason}` where `reason` is an
  atom describing the first validation failure encountered.
  """
  @spec parse(term()) :: {:ok, config()} | {:error, atom()}
  def parse(uri) when is_binary(uri) do
    parsed = URI.parse(uri)

    with :ok <- check_scheme(parsed),
         :ok <- check_type(parsed),
         {:ok, label_issuer, account} <- parse_label(parsed.path),
         params = URI.decode_query(parsed.query || ""),
         {:ok, secret} <- parse_secret(params),
         {:ok, issuer} <- resolve_issuer(label_issuer, params),
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
  Compute the TOTP code for `config` at the given UNIX timestamp (seconds).

  The result is a zero-padded decimal string of exactly `config.digits`
  characters, following RFC 6238 / RFC 4226 dynamic truncation.
  """
  @spec code_at(config(), integer()) :: String.t()
  def code_at(config, unix_time) do
    step = div(unix_time, config.period)
    counter = <<step::unsigned-big-integer-size(64)>>
    key = base32_decode(config.secret)
    mac = :crypto.mac(:hmac, hash_alg(config.algorithm), key, counter)

    offset = band(:binary.at(mac, byte_size(mac) - 1), 0x0F)
    <<_prefix::binary-size(offset), p0, p1, p2, p3, _rest::binary>> = mac

    value =
      bor(
        bor(bsl(band(p0, 0x7F), 24), bsl(p1, 16)),
        bor(bsl(p2, 8), p3)
      )

    modulo = Integer.pow(10, config.digits)

    value
    |> rem(modulo)
    |> Integer.to_string()
    |> String.pad_leading(config.digits, "0")
  end

  @doc """
  Return how many seconds the current code stays valid.

  This is `config.period - rem(unix_time, config.period)`; on an exact period
  boundary it returns the full period.
  """
  @spec seconds_remaining(config(), integer()) :: integer()
  def seconds_remaining(config, unix_time) do
    config.period - rem(unix_time, config.period)
  end

  @doc """
  Verify `code` against the code for the exact current step.

  There is no drift window — a code from the previous or next step is rejected.
  `code` may be a string or an integer; it is normalized to a zero-padded string
  of `config.digits` characters and compared in constant time.
  """
  @spec verify(config(), String.t() | integer(), integer()) :: boolean()
  def verify(config, code, unix_time) do
    expected = code_at(config, unix_time)
    given = normalize_code(code, config.digits)
    secure_compare(expected, given)
  end

  # --- URI structural checks --------------------------------------------------

  defp check_scheme(%URI{scheme: scheme}) when is_binary(scheme) do
    if String.downcase(scheme) == "otpauth", do: :ok, else: {:error, :invalid_scheme}
  end

  defp check_scheme(_parsed), do: {:error, :invalid_scheme}

  defp check_type(%URI{host: host}) when is_binary(host) do
    if String.downcase(host) == "totp", do: :ok, else: {:error, :unsupported_type}
  end

  defp check_type(_parsed), do: {:error, :unsupported_type}

  # --- Label parsing ----------------------------------------------------------

  defp parse_label(path) when is_binary(path) do
    stripped = String.replace_prefix(path, "/", "")
    decoded = URI.decode(stripped)

    case decoded do
      "" -> {:error, :missing_label}
      _label -> split_label(decoded)
    end
  end

  defp parse_label(_path), do: {:error, :missing_label}

  defp split_label(decoded) do
    case String.split(decoded, ":", parts: 2) do
      [account] ->
        validate_label(nil, account)

      [issuer, account_raw] ->
        validate_label(issuer, strip_leading_space(account_raw))
    end
  end

  defp strip_leading_space(" " <> rest), do: rest
  defp strip_leading_space(other), do: other

  defp validate_label(nil, account) do
    if account == "", do: {:error, :missing_label}, else: {:ok, nil, account}
  end

  defp validate_label(issuer, account) do
    cond do
      issuer == "" -> {:error, :missing_label}
      account == "" -> {:error, :missing_label}
      true -> {:ok, issuer, account}
    end
  end

  # --- Query parameter parsing ------------------------------------------------

  defp parse_secret(params) do
    case Map.get(params, "secret") do
      nil ->
        {:error, :missing_secret}

      raw ->
        normalized = raw |> String.replace(~r/[\s=]/, "") |> String.upcase()

        if normalized != "" and Regex.match?(~r/\A[A-Z2-7]+\z/, normalized) do
          {:ok, normalized}
        else
          {:error, :invalid_secret}
        end
    end
  end

  defp resolve_issuer(label_issuer, params) do
    case {label_issuer, Map.get(params, "issuer")} do
      {nil, nil} -> {:ok, nil}
      {nil, param} -> {:ok, param}
      {label, nil} -> {:ok, label}
      {label, param} when label == param -> {:ok, label}
      _mismatch -> {:error, :issuer_mismatch}
    end
  end

  defp parse_algorithm(params) do
    case Map.get(params, "algorithm") do
      nil ->
        {:ok, :sha1}

      raw ->
        case String.upcase(raw) do
          "SHA1" -> {:ok, :sha1}
          "SHA256" -> {:ok, :sha256}
          "SHA512" -> {:ok, :sha512}
          _other -> {:error, :unsupported_algorithm}
        end
    end
  end

  defp parse_digits(params) do
    case Map.get(params, "digits") do
      nil -> {:ok, 6}
      "6" -> {:ok, 6}
      "7" -> {:ok, 7}
      "8" -> {:ok, 8}
      _other -> {:error, :invalid_digits}
    end
  end

  defp parse_period(params) do
    case Map.get(params, "period") do
      nil -> {:ok, 30}
      raw -> validate_period(raw)
    end
  end

  defp validate_period(raw) do
    case Integer.parse(raw) do
      {n, ""} when n > 0 ->
        if Integer.to_string(n) == raw, do: {:ok, n}, else: {:error, :invalid_period}

      _other ->
        {:error, :invalid_period}
    end
  end

  # --- RFC 4648 base32 decoding -----------------------------------------------

  defp base32_decode(secret) do
    bits = for <<c <- secret>>, into: <<>>, do: <<base32_index(c)::5>>
    byte_count = div(bit_size(bits), 8)
    <<result::binary-size(byte_count), _leftover::bitstring>> = bits
    result
  end

  defp base32_index(c) when c in ?A..?Z, do: c - ?A
  defp base32_index(c) when c in ?2..?7, do: c - ?2 + 26

  # --- Helpers ----------------------------------------------------------------

  defp hash_alg(:sha1), do: :sha
  defp hash_alg(:sha256), do: :sha256
  defp hash_alg(:sha512), do: :sha512

  defp normalize_code(code, digits) when is_integer(code) do
    code |> Integer.to_string() |> String.pad_leading(digits, "0")
  end

  defp normalize_code(code, digits) when is_binary(code) do
    String.pad_leading(code, digits, "0")
  end

  defp secure_compare(a, b) when byte_size(a) == byte_size(b) do
    a_bytes = :binary.bin_to_list(a)
    b_bytes = :binary.bin_to_list(b)

    diff =
      a_bytes
      |> Enum.zip(b_bytes)
      |> Enum.reduce(0, fn {x, y}, acc -> bor(acc, bxor(x, y)) end)

    diff == 0
  end

  defp secure_compare(_a, _b), do: false
end