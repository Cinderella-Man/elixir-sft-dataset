defmodule AuthenticatorURI do
  @moduledoc """
  Parse an `otpauth://totp/...` provisioning URI into a validated configuration
  and then generate or verify TOTP codes from that configuration.

  This module goes the *opposite* direction from a typical TOTP generator: rather
  than building a provisioning URI from hard-coded parameters, it consumes a URI
  that some server placed in a QR code and honours *its* parameters. That means
  the hash algorithm (SHA1/SHA256/SHA512), the number of digits (6/7/8) and the
  time step (period) all come from the URI — never from constants baked into this
  code.

  Only the OTP standard library is used. RFC 4648 base32 decoding is implemented
  here directly; HMAC comes from `:crypto`.
  """

  import Bitwise

  @type config :: %{
          issuer: String.t() | nil,
          account: String.t(),
          secret: String.t(),
          algorithm: :sha1 | :sha256 | :sha512,
          digits: 6 | 7 | 8,
          period: pos_integer()
        }

  @doc """
  Parse an `otpauth://totp/...` URI into a validated `t:config/0` map.

  Returns `{:ok, config}` on success, or `{:error, reason}` where `reason` is an
  atom describing the first problem encountered. A non-binary argument yields
  `{:error, :invalid_scheme}`.
  """
  @spec parse(term()) :: {:ok, config()} | {:error, atom()}
  def parse(uri) when is_binary(uri) do
    parsed = URI.parse(uri)

    with :ok <- check_scheme(parsed),
         :ok <- check_type(parsed),
         {:ok, label_issuer, account} <- parse_label(get_label(parsed)),
         params = decode_params(parsed),
         {:ok, secret} <- validate_secret(params),
         {:ok, issuer} <- resolve_issuer(label_issuer, Map.get(params, "issuer")),
         {:ok, algorithm} <- validate_algorithm(params),
         {:ok, digits} <- validate_digits(params),
         {:ok, period} <- validate_period(params) do
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
  Return the TOTP code for `config` at the given UNIX timestamp (in seconds).

  The result is a string zero-padded on the left to exactly `config.digits`
  characters, following RFC 6238 / RFC 4226.
  """
  @spec code_at(config(), integer()) :: String.t()
  def code_at(config, unix_time) do
    %{secret: secret, algorithm: algorithm, digits: digits, period: period} = config

    step = div(unix_time, period)
    counter = <<step::unsigned-big-integer-size(64)>>
    key = base32_decode(secret)
    hmac = :crypto.mac(:hmac, hash_algorithm(algorithm), key, counter)

    offset = :binary.at(hmac, byte_size(hmac) - 1) &&& 0x0F
    <<truncated::unsigned-big-integer-size(32)>> = binary_part(hmac, offset, 4)

    code = (truncated &&& 0x7FFFFFFF) |> rem(Integer.pow(10, digits))

    code
    |> Integer.to_string()
    |> String.pad_leading(digits, "0")
  end

  @doc """
  Return how many seconds the current code stays valid.

  This is `config.period - rem(unix_time, config.period)`; on an exact period
  boundary it returns the full period.
  """
  @spec seconds_remaining(config(), integer()) :: integer()
  def seconds_remaining(%{period: period}, unix_time) do
    period - rem(unix_time, period)
  end

  @doc """
  Verify `code` against the code for the *exact* current step.

  Returns `true` only on a match; there is no drift window, so codes from the
  previous or next step are rejected. `code` may be a string or an integer and is
  normalized by zero-padding on the left to `config.digits` characters, then
  compared using a constant-time (non-short-circuiting) byte comparison.
  """
  @spec verify(config(), String.t() | integer(), integer()) :: boolean()
  def verify(config, code, unix_time) do
    expected = code_at(config, unix_time)
    provided = normalize_code(code, config.digits)
    secure_compare(provided, expected)
  end

  # --- Parsing helpers -----------------------------------------------------

  defp check_scheme(%URI{scheme: scheme}) when is_binary(scheme) do
    if String.downcase(scheme) == "otpauth" do
      :ok
    else
      {:error, :invalid_scheme}
    end
  end

  defp check_scheme(_parsed), do: {:error, :invalid_scheme}

  defp check_type(%URI{host: host}) when is_binary(host) do
    if String.downcase(host) == "totp" do
      :ok
    else
      {:error, :unsupported_type}
    end
  end

  defp check_type(_parsed), do: {:error, :unsupported_type}

  defp get_label(%URI{path: "/" <> rest}), do: URI.decode(rest)
  defp get_label(_parsed), do: ""

  defp parse_label(""), do: {:error, :missing_label}

  defp parse_label(label) do
    case String.split(label, ":", parts: 2) do
      [account] ->
        if account == "", do: {:error, :missing_label}, else: {:ok, nil, account}

      [issuer, rest] ->
        account = strip_leading_space(rest)

        if issuer == "" or account == "" do
          {:error, :missing_label}
        else
          {:ok, issuer, account}
        end
    end
  end

  defp strip_leading_space(" " <> rest), do: rest
  defp strip_leading_space(rest), do: rest

  defp decode_params(%URI{query: nil}), do: %{}
  defp decode_params(%URI{query: query}), do: URI.decode_query(query)

  defp validate_secret(params) do
    case Map.get(params, "secret") do
      nil ->
        {:error, :missing_secret}

      raw ->
        normalized =
          raw
          |> String.replace(~r/[\s=]/, "")
          |> String.upcase()

        if normalized != "" and Regex.match?(~r/\A[A-Z2-7]+\z/, normalized) do
          {:ok, normalized}
        else
          {:error, :invalid_secret}
        end
    end
  end

  defp resolve_issuer(label_issuer, param_issuer) do
    cond do
      is_binary(label_issuer) and is_binary(param_issuer) ->
        if label_issuer == param_issuer do
          {:ok, label_issuer}
        else
          {:error, :issuer_mismatch}
        end

      is_binary(label_issuer) ->
        {:ok, label_issuer}

      is_binary(param_issuer) ->
        {:ok, param_issuer}

      true ->
        {:ok, nil}
    end
  end

  defp validate_algorithm(params) do
    case params |> Map.get("algorithm", "SHA1") |> String.upcase() do
      "SHA1" -> {:ok, :sha1}
      "SHA256" -> {:ok, :sha256}
      "SHA512" -> {:ok, :sha512}
      _other -> {:error, :unsupported_algorithm}
    end
  end

  defp validate_digits(params) do
    case Map.get(params, "digits", "6") do
      "6" -> {:ok, 6}
      "7" -> {:ok, 7}
      "8" -> {:ok, 8}
      _other -> {:error, :invalid_digits}
    end
  end

  defp validate_period(params) do
    raw = Map.get(params, "period", "30")

    case Integer.parse(raw) do
      {value, ""} when value > 0 ->
        if Integer.to_string(value) == raw do
          {:ok, value}
        else
          {:error, :invalid_period}
        end

      _other ->
        {:error, :invalid_period}
    end
  end

  # --- Code generation helpers --------------------------------------------

  defp hash_algorithm(:sha1), do: :sha
  defp hash_algorithm(:sha256), do: :sha256
  defp hash_algorithm(:sha512), do: :sha512

  defp normalize_code(code, digits) when is_integer(code) do
    code
    |> Integer.to_string()
    |> String.pad_leading(digits, "0")
  end

  defp normalize_code(code, digits) when is_binary(code) do
    String.pad_leading(code, digits, "0")
  end

  # RFC 4648 base32 decoding (uppercase alphabet A-Z plus 2-7, no padding).
  # Leftover bits that do not complete a whole byte are discarded.
  defp base32_decode(secret) do
    {_acc, _bits, bytes} =
      secret
      |> String.to_charlist()
      |> Enum.reduce({0, 0, []}, &base32_step/2)

    bytes
    |> Enum.reverse()
    |> :erlang.list_to_binary()
  end

  defp base32_step(char, {acc, bits, bytes}) do
    acc = (acc <<< 5) ||| base32_value(char)
    bits = bits + 5

    if bits >= 8 do
      shift = bits - 8
      byte = (acc >>> shift) &&& 0xFF
      acc = acc &&& ((1 <<< shift) - 1)
      {acc, shift, [byte | bytes]}
    else
      {acc, bits, bytes}
    end
  end

  defp base32_value(char) when char in ?A..?Z, do: char - ?A
  defp base32_value(char) when char in ?2..?7, do: char - ?2 + 26

  # Constant-time comparison: fold every byte with bitwise OR of XOR diffs so no
  # byte position can short-circuit the result. Unequal lengths fail up front.
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