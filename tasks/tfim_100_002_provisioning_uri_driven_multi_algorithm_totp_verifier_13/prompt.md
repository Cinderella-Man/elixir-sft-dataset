# Complete the blanked test

You get a module and its ExUnit harness, minus the body of ONE `test` —
the `# TODO` marks the spot, and its name says what it must prove. Write
exactly that test so the harness passes against a correct implementation
of the module.

## Module under test

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

  @spec validate_type(String.t() | nil) :: :ok | {:error, :unsupported_type}
  defp validate_type(host) when is_binary(host) do
    if String.downcase(host) == "totp", do: :ok, else: {:error, :unsupported_type}
  end

  defp validate_type(_host), do: {:error, :unsupported_type}

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

## Test harness — implement the `# TODO` test

```elixir
defmodule AuthenticatorURITest do
  use ExUnit.Case, async: false

  # RFC 6238 test seeds, base32-encoded (RFC 4648, unpadded).
  #   SHA1:   "12345678901234567890"                                             (20 bytes)
  #   SHA256: "12345678901234567890123456789012"                                 (32 bytes)
  #   SHA512: "1234567890123456789012345678901234567890123456789012345678901234" (64 bytes)
  @sha1_secret "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"
  @sha256_secret "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZA"
  @sha512_secret "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNA"

  defp uri(params) do
    query = URI.encode_query(params)
    "otpauth://totp/Acme:alice@example.com?" <> query
  end

  defp config!(params) do
    {:ok, config} = AuthenticatorURI.parse(uri(params))
    config
  end

  # ------------------------------------------------------------------
  # parse/1 — happy path and defaults
  # ------------------------------------------------------------------

  test "parse returns a full config map" do
    assert {:ok, config} =
             AuthenticatorURI.parse(
               "otpauth://totp/Acme:alice@example.com?secret=#{@sha1_secret}&algorithm=SHA256&digits=8&period=60"
             )

    assert config == %{
             issuer: "Acme",
             account: "alice@example.com",
             secret: @sha1_secret,
             algorithm: :sha256,
             digits: 8,
             period: 60
           }
  end

  test "parse applies defaults for algorithm, digits and period" do
    config = config!(secret: @sha1_secret)
    assert config.algorithm == :sha1
    assert config.digits == 6
    assert config.period == 30
  end

  test "parse accepts a label with no issuer and no issuer param" do
    assert {:ok, config} =
             AuthenticatorURI.parse("otpauth://totp/alice@example.com?secret=#{@sha1_secret}")

    assert config.issuer == nil
    assert config.account == "alice@example.com"
  end

  test "parse takes the issuer from the query param when the label has none" do
    assert {:ok, config} =
             AuthenticatorURI.parse(
               "otpauth://totp/alice@example.com?secret=#{@sha1_secret}&issuer=Acme"
             )

    assert config.issuer == "Acme"
    assert config.account == "alice@example.com"
  end

  test "parse percent-decodes the label" do
    assert {:ok, config} =
             AuthenticatorURI.parse(
               "otpauth://totp/Acme%20Co:alice%40example.com?secret=#{@sha1_secret}"
             )

    assert config.issuer == "Acme Co"
    assert config.account == "alice@example.com"
  end

  test "parse strips a single space after the label colon" do
    assert {:ok, config} =
             AuthenticatorURI.parse("otpauth://totp/Acme:%20alice?secret=#{@sha1_secret}")

    assert config.issuer == "Acme"
    assert config.account == "alice"
  end

  test "parse accepts a matching issuer in both label and query param" do
    assert {:ok, config} =
             AuthenticatorURI.parse(
               "otpauth://totp/Acme%20Co:alice?secret=#{@sha1_secret}&issuer=Acme+Co"
             )

    assert config.issuer == "Acme Co"
  end

  test "parse normalizes a lowercase, padded, whitespace-y secret" do
    raw = String.downcase(@sha1_secret) <> "===="

    assert {:ok, config} =
             AuthenticatorURI.parse("otpauth://totp/Acme:alice?secret=#{URI.encode(raw)}")

    assert config.secret == @sha1_secret
  end

  # QR payloads commonly group the secret into space-separated blocks; every
  # space must disappear from the normalized secret, which then keys the HMAC.
  test "parse strips spaces from a space-grouped secret" do
    grouped = "GEZD GNBV GY3T QOJQ GEZD GNBV GY3T QOJQ"

    assert {:ok, config} = AuthenticatorURI.parse(uri(secret: grouped))
    assert config.secret == @sha1_secret
    assert AuthenticatorURI.code_at(config, 59) == "287082"
  end

  # Tabs are whitespace too, and stripping happens alongside padding removal
  # and upcasing rather than instead of them.
  test "parse strips tabs alongside spaces, padding and lowercase" do
    raw = "gezd\tgnbv gy3t qojq\tgezd gnbv gy3t qojq===="

    assert {:ok, config} = AuthenticatorURI.parse(uri(secret: raw))
    assert config.secret == @sha1_secret
  end

  test "parse accepts each supported algorithm spelling case-insensitively" do
    assert config!(secret: @sha1_secret, algorithm: "sha1").algorithm == :sha1
    assert config!(secret: @sha256_secret, algorithm: "Sha256").algorithm == :sha256
    assert config!(secret: @sha512_secret, algorithm: "SHA512").algorithm == :sha512
  end

  test "parse accepts digits 6, 7 and 8" do
    assert config!(secret: @sha1_secret, digits: "6").digits == 6
    assert config!(secret: @sha1_secret, digits: "7").digits == 7
    assert config!(secret: @sha1_secret, digits: "8").digits == 8
  end

  # ------------------------------------------------------------------
  # parse/1 — error semantics
  # ------------------------------------------------------------------

  test "parse rejects a non-otpauth scheme" do
    assert AuthenticatorURI.parse("https://totp/Acme:alice?secret=#{@sha1_secret}") ==
             {:error, :invalid_scheme}
  end

  test "parse rejects a non-binary argument" do
    # TODO
  end

  test "parse rejects the hotp type" do
    assert AuthenticatorURI.parse("otpauth://hotp/Acme:alice?secret=#{@sha1_secret}&counter=1") ==
             {:error, :unsupported_type}
  end

  test "parse rejects an empty or malformed label" do
    assert AuthenticatorURI.parse("otpauth://totp/?secret=#{@sha1_secret}") ==
             {:error, :missing_label}

    assert AuthenticatorURI.parse("otpauth://totp/Acme:?secret=#{@sha1_secret}") ==
             {:error, :missing_label}

    assert AuthenticatorURI.parse("otpauth://totp/:alice?secret=#{@sha1_secret}") ==
             {:error, :missing_label}
  end

  test "parse rejects a missing secret" do
    assert AuthenticatorURI.parse("otpauth://totp/Acme:alice?issuer=Acme") ==
             {:error, :missing_secret}
  end

  test "parse rejects a secret with non-base32 characters" do
    assert AuthenticatorURI.parse("otpauth://totp/Acme:alice?secret=ABC1DEF") ==
             {:error, :invalid_secret}

    assert AuthenticatorURI.parse("otpauth://totp/Acme:alice?secret=ABC%21DEF") ==
             {:error, :invalid_secret}
  end

  test "parse rejects a secret that normalizes to the empty string" do
    assert AuthenticatorURI.parse("otpauth://totp/Acme:alice?secret=%3D%3D%3D") ==
             {:error, :invalid_secret}
  end

  # Whitespace is removed before the emptiness check, so a blank secret is
  # invalid rather than accepted as a literal run of spaces.
  test "parse rejects a whitespace-only secret" do
    assert AuthenticatorURI.parse(uri(secret: "  \t ")) == {:error, :invalid_secret}
  end

  test "parse rejects an issuer mismatch between label and query param" do
    assert AuthenticatorURI.parse("otpauth://totp/Acme:alice?secret=#{@sha1_secret}&issuer=Other") ==
             {:error, :issuer_mismatch}
  end

  test "parse rejects an unsupported algorithm" do
    assert AuthenticatorURI.parse(
             "otpauth://totp/Acme:alice?secret=#{@sha1_secret}&algorithm=MD5"
           ) == {:error, :unsupported_algorithm}
  end

  test "parse rejects unsupported digit counts" do
    assert AuthenticatorURI.parse("otpauth://totp/Acme:alice?secret=#{@sha1_secret}&digits=9") ==
             {:error, :invalid_digits}

    assert AuthenticatorURI.parse("otpauth://totp/Acme:alice?secret=#{@sha1_secret}&digits=5") ==
             {:error, :invalid_digits}

    assert AuthenticatorURI.parse("otpauth://totp/Acme:alice?secret=#{@sha1_secret}&digits=six") ==
             {:error, :invalid_digits}

    assert AuthenticatorURI.parse("otpauth://totp/Acme:alice?secret=#{@sha1_secret}&digits=6x") ==
             {:error, :invalid_digits}
  end

  test "parse rejects invalid periods" do
    assert AuthenticatorURI.parse("otpauth://totp/Acme:alice?secret=#{@sha1_secret}&period=0") ==
             {:error, :invalid_period}

    assert AuthenticatorURI.parse("otpauth://totp/Acme:alice?secret=#{@sha1_secret}&period=-30") ==
             {:error, :invalid_period}

    assert AuthenticatorURI.parse("otpauth://totp/Acme:alice?secret=#{@sha1_secret}&period=abc") ==
             {:error, :invalid_period}
  end

  test "parse accepts a non-default period" do
    assert config!(secret: @sha1_secret, period: "90").period == 90
  end

  # ------------------------------------------------------------------
  # code_at/2 — RFC 6238 vectors (8 digits, period 30)
  # ------------------------------------------------------------------

  for {t, expected} <- [
        {59, "94287082"},
        {1_111_111_109, "07081804"},
        {1_111_111_111, "14050471"},
        {1_234_567_890, "89005924"},
        {2_000_000_000, "69279037"},
        {20_000_000_000, "65353130"}
      ] do
    test "SHA1 8-digit RFC vector at t=#{t}" do
      config = config!(secret: @sha1_secret, algorithm: "SHA1", digits: "8")
      assert AuthenticatorURI.code_at(config, unquote(t)) == unquote(expected)
    end
  end

  for {t, expected} <- [
        {59, "46119246"},
        {1_111_111_109, "68084774"},
        {1_111_111_111, "67062674"},
        {1_234_567_890, "91819424"},
        {2_000_000_000, "90698825"},
        {20_000_000_000, "77737706"}
      ] do
    test "SHA256 8-digit RFC vector at t=#{t}" do
      config = config!(secret: @sha256_secret, algorithm: "SHA256", digits: "8")
      assert AuthenticatorURI.code_at(config, unquote(t)) == unquote(expected)
    end
  end

  for {t, expected} <- [
        {59, "90693936"},
        {1_111_111_109, "25091201"},
        {1_111_111_111, "99943326"},
        {1_234_567_890, "93441116"},
        {2_000_000_000, "38618901"},
        {20_000_000_000, "47863826"}
      ] do
    test "SHA512 8-digit RFC vector at t=#{t}" do
      config = config!(secret: @sha512_secret, algorithm: "SHA512", digits: "8")
      assert AuthenticatorURI.code_at(config, unquote(t)) == unquote(expected)
    end
  end

  # ------------------------------------------------------------------
  # code_at/2 — digits and period handling
  # ------------------------------------------------------------------

  test "6-digit codes are the truncation of the same counter" do
    config = config!(secret: @sha1_secret)
    assert AuthenticatorURI.code_at(config, 1_234_567_890) == "005924"
    assert AuthenticatorURI.code_at(config, 59) == "287082"
  end

  test "7-digit codes are the truncation of the same counter" do
    config = config!(secret: @sha1_secret, digits: "7")
    assert AuthenticatorURI.code_at(config, 1_234_567_890) == "9005924"
    assert AuthenticatorURI.code_at(config, 59) == "4287082"
  end

  test "code length always equals the configured digit count" do
    for d <- ["6", "7", "8"] do
      config = config!(secret: @sha1_secret, digits: d)
      code = AuthenticatorURI.code_at(config, 1_234_567_890)
      assert byte_size(code) == config.digits
      assert String.match?(code, ~r/\A\d+\z/)
    end
  end

  test "code is stable across a period and changes at the boundary" do
    config = config!(secret: @sha1_secret)

    assert AuthenticatorURI.code_at(config, 1_111_111_111) ==
             AuthenticatorURI.code_at(config, 1_111_111_139)

    refute AuthenticatorURI.code_at(config, 1_111_111_109) ==
             AuthenticatorURI.code_at(config, 1_111_111_111)
  end

  test "a different period yields a different counter" do
    p30 = config!(secret: @sha1_secret)
    p60 = config!(secret: @sha1_secret, period: "60")

    # div(59, 30) == 1 while div(59, 60) == 0, so the codes come from
    # different counters.
    assert AuthenticatorURI.code_at(p30, 59) == "287082"
    assert AuthenticatorURI.code_at(p60, 59) == AuthenticatorURI.code_at(p30, 0)
  end

  # ------------------------------------------------------------------
  # seconds_remaining/2
  # ------------------------------------------------------------------

  test "seconds_remaining counts down within a period" do
    config = config!(secret: @sha1_secret)
    assert AuthenticatorURI.seconds_remaining(config, 1_111_111_111) == 29
    assert AuthenticatorURI.seconds_remaining(config, 1_111_111_139) == 1
  end

  test "seconds_remaining returns the full period on a boundary" do
    config = config!(secret: @sha1_secret)
    assert AuthenticatorURI.seconds_remaining(config, 1_111_111_110) == 30
  end

  test "seconds_remaining honours a custom period" do
    config = config!(secret: @sha1_secret, period: "60")
    assert AuthenticatorURI.seconds_remaining(config, 1_111_111_111) == 29
    assert AuthenticatorURI.seconds_remaining(config, 1_111_111_080) == 60
  end

  # ------------------------------------------------------------------
  # verify/3
  # ------------------------------------------------------------------

  test "verify accepts the code for the current step" do
    config = config!(secret: @sha1_secret)
    assert AuthenticatorURI.verify(config, "005924", 1_234_567_890)
    assert AuthenticatorURI.verify(config, AuthenticatorURI.code_at(config, 59), 59)
  end

  test "verify accepts an integer code, zero-padding it" do
    config = config!(secret: @sha1_secret)
    assert AuthenticatorURI.verify(config, 5924, 1_234_567_890)
  end

  test "verify rejects a wrong code" do
    config = config!(secret: @sha1_secret)
    refute AuthenticatorURI.verify(config, "999999", 1_234_567_890)
    refute AuthenticatorURI.verify(config, "12345", 1_234_567_890)
  end

  test "verify has no drift window: adjacent steps are rejected" do
    config = config!(secret: @sha1_secret)

    previous = AuthenticatorURI.code_at(config, 1_111_111_109)
    current = AuthenticatorURI.code_at(config, 1_111_111_111)
    following = AuthenticatorURI.code_at(config, 1_111_111_141)

    assert AuthenticatorURI.verify(config, current, 1_111_111_111)
    refute AuthenticatorURI.verify(config, previous, 1_111_111_111)
    refute AuthenticatorURI.verify(config, following, 1_111_111_111)
  end

  test "verify works for 8-digit SHA512 configs" do
    config = config!(secret: @sha512_secret, algorithm: "SHA512", digits: "8")
    assert AuthenticatorURI.verify(config, "93441116", 1_234_567_890)
    refute AuthenticatorURI.verify(config, "93441117", 1_234_567_890)
  end
end
```
