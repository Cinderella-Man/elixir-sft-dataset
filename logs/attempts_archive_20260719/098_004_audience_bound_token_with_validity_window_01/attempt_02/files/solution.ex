defmodule ScopedToken do
  @moduledoc """
  Generation and validation of signed, audience-bound tokens with a validity
  window, backed only by an HMAC-SHA256 signature — no database or persistent
  state.

  A token binds an arbitrary Elixir payload to:

    * an **audience** label (for example `"web"` or `"mobile"`), so a token
      issued for one audience will not verify for another, and
    * a **validity window** with both a not-before time and an expiry, so a
      token can be issued to become valid only at some point in the future and
      to stop being valid once it expires.

  The wire format is a URL-safe (unpadded) Base64 encoding of:

      <<
        issued_at::64,
        not_before_at::64,
        expires_at::64,
        aud_len::32, audience::binary,
        payload_len::32, payload::binary,
        mac::binary-size(32)
      >>

  The 32-byte trailing MAC is an HMAC-SHA256 over every preceding byte, so the
  audience, all three timestamps, the payload and their length prefixes are all
  covered by the signature and cannot be tampered with independently.
  """

  @mac_size 32

  @doc """
  Generate a URL-safe signed token.

  `payload` is any Elixir term, `secret` is the binary HMAC key, `audience` is
  the binary label the token is bound to, and `ttl_seconds` is a positive
  integer number of seconds until expiry.

  The expiration is `issued_at + ttl_seconds`. The not-before timestamp is
  `issued_at + not_before`, where `not_before` comes from `opts` and defaults
  to `0` (making the token immediately valid).

  ## Options

    * `:clock` — a zero-arity function returning a Unix epoch second. Defaults
      to `System.os_time(:second)`. This is a test seam only.
    * `:not_before` — a non-negative integer number of seconds after the issue
      time before which the token is not valid. Defaults to `0`.

  Returns the token as a URL-safe binary with no padding characters.
  """
  @spec generate(term(), binary(), binary(), pos_integer(), keyword()) :: binary()
  def generate(payload, secret, audience, ttl_seconds, opts \\ [])
      when is_binary(secret) and is_binary(audience) and is_integer(ttl_seconds) and
             ttl_seconds > 0 and is_list(opts) do
    not_before = Keyword.get(opts, :not_before, 0)

    unless is_integer(not_before) and not_before >= 0 do
      raise ArgumentError, ":not_before must be a non-negative integer"
    end

    issued_at = now(opts)
    not_before_at = issued_at + not_before
    expires_at = issued_at + ttl_seconds

    payload_bin = :erlang.term_to_binary(payload)

    signed =
      <<
        issued_at::64,
        not_before_at::64,
        expires_at::64,
        byte_size(audience)::32,
        audience::binary,
        byte_size(payload_bin)::32,
        payload_bin::binary
      >>

    mac = :crypto.mac(:hmac, :sha256, secret, signed)
    Base.url_encode64(signed <> mac, padding: false)
  end

  @doc """
  Decode and validate `token` against `expected_audience`.

  Returns `{:ok, payload}` when the signature is valid, the token's audience
  exactly equals `expected_audience`, and the current time is within the
  validity window (at or after the not-before time and strictly before the
  expiry).

  Otherwise returns one of `{:error, reason}` where `reason` is:

    * `:invalid_signature` — the structure parses but the HMAC does not match.
    * `:audience_mismatch` — signature valid, but audience differs.
    * `:not_yet_valid` — signature and audience fine, but before not-before.
    * `:expired` — signature and audience fine and past the not-before window,
      but at or past the expiry.
    * `:malformed` — anything that cannot be decoded at all (bad base64, too
      short, header not matching the remaining bytes, non-binary input, or a
      post-HMAC payload deserialization failure).

  The checks run in this exact order: base64 decode, split off the trailing
  32-byte MAC, structural parse of the header, HMAC verification, audience
  match, not-before check, expiry check, payload deserialization.

  ## Options

    * `:clock` — a zero-arity function returning a Unix epoch second. Defaults
      to `System.os_time(:second)`. This is a test seam only.
  """
  @spec verify(binary(), binary(), binary(), keyword()) ::
          {:ok, term()}
          | {:error,
             :invalid_signature
             | :audience_mismatch
             | :not_yet_valid
             | :expired
             | :malformed}
  def verify(token, secret, expected_audience, opts \\ [])
      when is_binary(secret) and is_binary(expected_audience) and is_list(opts) do
    with :ok <- ensure_binary(token),
         {:ok, decoded} <- decode(token),
         {:ok, signed, mac} <- split_mac(decoded),
         {:ok, fields} <- parse(signed),
         :ok <- check_mac(secret, signed, mac),
         :ok <- check_audience(fields.audience, expected_audience),
         :ok <- check_not_before(fields.not_before_at, opts),
         :ok <- check_expiry(fields.expires_at, opts),
         {:ok, payload} <- deserialize(fields.payload) do
      {:ok, payload}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  # -- internal helpers ------------------------------------------------------

  @spec ensure_binary(term()) :: :ok | {:error, :malformed}
  defp ensure_binary(token) when is_binary(token), do: :ok
  defp ensure_binary(_token), do: {:error, :malformed}

  @spec now(keyword()) :: integer()
  defp now(opts) do
    case Keyword.get(opts, :clock) do
      nil -> System.os_time(:second)
      clock when is_function(clock, 0) -> clock.()
    end
  end

  @spec decode(binary()) :: {:ok, binary()} | {:error, :malformed}
  defp decode(token) do
    case Base.url_decode64(token, padding: false) do
      {:ok, decoded} -> {:ok, decoded}
      :error -> {:error, :malformed}
    end
  end

  @spec split_mac(binary()) :: {:ok, binary(), binary()} | {:error, :malformed}
  defp split_mac(decoded) when byte_size(decoded) < @mac_size do
    {:error, :malformed}
  end

  defp split_mac(decoded) do
    signed_size = byte_size(decoded) - @mac_size
    <<signed::binary-size(signed_size), mac::binary-size(@mac_size)>> = decoded
    {:ok, signed, mac}
  end

  @spec parse(binary()) :: {:ok, map()} | {:error, :malformed}
  defp parse(<<
         issued_at::64,
         not_before_at::64,
         expires_at::64,
         aud_len::32,
         audience::binary-size(aud_len),
         payload_len::32,
         payload::binary-size(payload_len)
       >>) do
    {:ok,
     %{
       issued_at: issued_at,
       not_before_at: not_before_at,
       expires_at: expires_at,
       audience: audience,
       payload: payload
     }}
  end

  defp parse(_other), do: {:error, :malformed}

  @spec check_mac(binary(), binary(), binary()) :: :ok | {:error, :invalid_signature}
  defp check_mac(secret, signed, mac) do
    expected = :crypto.mac(:hmac, :sha256, secret, signed)

    if secure_compare(expected, mac) do
      :ok
    else
      {:error, :invalid_signature}
    end
  end

  @spec check_audience(binary(), binary()) :: :ok | {:error, :audience_mismatch}
  defp check_audience(audience, expected_audience) do
    if secure_compare(audience, expected_audience) do
      :ok
    else
      {:error, :audience_mismatch}
    end
  end

  @spec check_not_before(integer(), keyword()) :: :ok | {:error, :not_yet_valid}
  defp check_not_before(not_before_at, opts) do
    if now(opts) >= not_before_at do
      :ok
    else
      {:error, :not_yet_valid}
    end
  end

  @spec check_expiry(integer(), keyword()) :: :ok | {:error, :expired}
  defp check_expiry(expires_at, opts) do
    if now(opts) < expires_at do
      :ok
    else
      {:error, :expired}
    end
  end

  @spec deserialize(binary()) :: {:ok, term()} | {:error, :malformed}
  defp deserialize(payload) do
    {:ok, :erlang.binary_to_term(payload, [:safe])}
  rescue
    ArgumentError -> {:error, :malformed}
  end

  # Constant-time comparison: compares every byte without short-circuiting on
  # the first difference. Returns `false` immediately only on length mismatch.
  @spec secure_compare(binary(), binary()) :: boolean()
  defp secure_compare(left, right)
       when is_binary(left) and is_binary(right) and byte_size(left) == byte_size(right) do
    secure_compare(left, right, 0) == 0
  end

  defp secure_compare(_left, _right), do: false

  @spec secure_compare(binary(), binary(), non_neg_integer()) :: non_neg_integer()
  defp secure_compare(<<x, left::binary>>, <<y, right::binary>>, acc) do
    import Bitwise
    secure_compare(left, right, acc ||| bxor(x, y))
  end

  defp secure_compare(<<>>, <<>>, acc), do: acc
end
