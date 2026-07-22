defmodule RotatingToken do
  @moduledoc """
  Signed, expiring HMAC-SHA256 tokens with signing-key rotation.

  Each token names the key that signed it via an embedded key id (`kid`).
  Verification looks the `kid` up in a keyring (`%{kid => secret}`), so old
  keys can be retired while previously issued tokens remain verifiable as
  long as their key stays in the ring.

  ## Wire format

  The decoded binary (before base64) is:

      <<issued_at::signed-64, expires_at::signed-64,
        kid_len::unsigned-8, kid::binary, payload_size::unsigned-32,
        payload::binary, mac::binary-32>>

  The `kid` (and everything else) is covered by the MAC.

  ## Clock injection

  `generate/5` and `verify/3` accept an optional `:clock` keyword whose
  value is a zero-arity function returning a Unix epoch second. When
  omitted, `System.os_time(:second)` is used — a test seam only.
  """

  @hmac_size 32

  @type reason :: :expired | :invalid_signature | :unknown_key | :malformed

  @doc """
  Build a URL-safe, signed, expiring token for `payload`.

  The token is signed with `secret` under the key id `kid` (at most 255
  bytes) and expires `ttl_seconds` (a positive integer) after issuance.
  The returned binary is produced by `Base.url_encode64/2` with
  `padding: false` and encodes the payload, issue and expiration
  timestamps, the `kid`, and an HMAC-SHA256 signature over all of it
  (including the `kid`).

  Pass a zero-arity `:clock` function in `opts` to override the clock used
  for the issue timestamp; it defaults to `System.os_time(:second)`.
  """
  @spec generate(term(), binary(), binary(), pos_integer(), keyword()) :: binary()
  def generate(payload, secret, kid, ttl_seconds, opts \\ [])
      when is_binary(secret) and is_binary(kid) and byte_size(kid) <= 255 and
             is_integer(ttl_seconds) and ttl_seconds > 0 do
    issued_at = now(opts)
    expires_at = issued_at + ttl_seconds
    kid_len = byte_size(kid)
    payload_bytes = :erlang.term_to_binary(payload)
    payload_size = byte_size(payload_bytes)

    data =
      <<issued_at::signed-64, expires_at::signed-64, kid_len::unsigned-8, kid::binary,
        payload_size::unsigned-32, payload_bytes::binary>>

    mac = :crypto.mac(:hmac, :sha256, secret, data)
    Base.url_encode64(<<data::binary, mac::binary>>, padding: false)
  end

  @doc """
  Decode and validate `token` against `keyring`, a `%{kid => secret}` map.

  Checks run in order: base64 decode → split off the trailing 32-byte MAC →
  structural parse (reading the embedded `kid`) → key lookup by `kid` →
  HMAC verification → expiry check → payload deserialization.

  Returns:

    * `{:ok, payload}` when the key is known, the signature is valid, and the
      token has not expired;
    * `{:error, :unknown_key}` when the token parses but its `kid` is absent
      from `keyring`;
    * `{:error, :invalid_signature}` when the key is known but the MAC differs;
    * `{:error, :expired}` when the signature is valid but the current time is
      at or past `expires_at`;
    * `{:error, :malformed}` for anything that cannot be decoded at all.

  Pass a zero-arity `:clock` function in `opts` to override the clock used for
  the expiry comparison; it defaults to `System.os_time(:second)`.
  """
  @spec verify(term(), %{optional(binary()) => binary()}, keyword()) ::
          {:ok, term()} | {:error, reason()}
  def verify(token, keyring, opts \\ [])

  def verify(token, keyring, opts) when is_binary(token) and is_map(keyring) do
    with {:ok, decoded} <- decode_base64(token),
         {:ok, data, mac} <- split_mac(decoded),
         {:ok, _issued_at, expires_at, kid, payload_bytes} <- parse_data(data),
         {:ok, secret} <- lookup_key(keyring, kid),
         :ok <- verify_mac(secret, data, mac),
         :ok <- check_expiry(expires_at, opts),
         {:ok, payload} <- decode_payload(payload_bytes) do
      {:ok, payload}
    end
  end

  def verify(_token, _keyring, _opts), do: {:error, :malformed}

  # --- Internal helpers --------------------------------------------------

  defp lookup_key(keyring, kid) do
    case Map.fetch(keyring, kid) do
      {:ok, secret} when is_binary(secret) -> {:ok, secret}
      _ -> {:error, :unknown_key}
    end
  end

  defp now(opts) do
    case Keyword.get(opts, :clock) do
      nil -> System.os_time(:second)
      fun when is_function(fun, 0) -> fun.()
    end
  end

  defp decode_base64(token) do
    case Base.url_decode64(token, padding: false) do
      {:ok, binary} -> {:ok, binary}
      :error -> {:error, :malformed}
    end
  end

  defp split_mac(binary) when byte_size(binary) < @hmac_size, do: {:error, :malformed}

  defp split_mac(binary) do
    data_size = byte_size(binary) - @hmac_size
    <<data::binary-size(data_size), mac::binary-size(@hmac_size)>> = binary
    {:ok, data, mac}
  end

  defp parse_data(
         <<issued_at::signed-64, expires_at::signed-64, kid_len::unsigned-8,
           kid::binary-size(kid_len), payload_size::unsigned-32, rest::binary>>
       )
       when byte_size(rest) == payload_size do
    {:ok, issued_at, expires_at, kid, rest}
  end

  defp parse_data(_), do: {:error, :malformed}

  defp verify_mac(secret, data, mac) do
    expected = :crypto.mac(:hmac, :sha256, secret, data)

    if constant_time_equal?(expected, mac) do
      :ok
    else
      {:error, :invalid_signature}
    end
  end

  defp check_expiry(expires_at, opts) do
    if now(opts) < expires_at, do: :ok, else: {:error, :expired}
  end

  defp decode_payload(bytes) do
    {:ok, :erlang.binary_to_term(bytes, [:safe])}
  rescue
    ArgumentError -> {:error, :malformed}
  end

  # Constant-time comparison: fold every byte with a bitwise-or of the
  # per-byte XORs so the loop never exits early on the first differing byte.
  defp constant_time_equal?(a, b) when byte_size(a) == byte_size(b) do
    constant_time_equal?(a, b, 0)
  end

  defp constant_time_equal?(_, _), do: false

  defp constant_time_equal?(<<x, a::binary>>, <<y, b::binary>>, acc) do
    constant_time_equal?(a, b, Bitwise.bor(acc, Bitwise.bxor(x, y)))
  end

  defp constant_time_equal?(<<>>, <<>>, acc), do: acc === 0
end