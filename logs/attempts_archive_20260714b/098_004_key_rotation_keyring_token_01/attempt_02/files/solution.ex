defmodule RotatingToken do
  @moduledoc """
  Signed, expiring tokens validated against a *keyring* of multiple secrets.

  A keyring is a map `%{key_id => secret}` where `key_id` ("kid") is a binary
  identifier and `secret` is a binary HMAC signing key. Every token records the
  key id that signed it, and `verify/3` looks that id up in a caller-supplied
  keyring. This lets you rotate signing keys without invalidating tokens still
  in flight: keep the old id in the keyring while both are valid, then drop it
  to retire every token it signed (they become `{:error, :unknown_key}`).

  Tokens are URL-safe (`Base.url_encode64/2` with `padding: false`) and carry,
  inside a single HMAC-SHA256 signed region, the key id, the payload, and the
  issue and expiry timestamps. Because the key id lives inside the signed
  region, it cannot be swapped without invalidating the signature.

  There is no database or persistent state. The only non-pure input is the
  clock, which can be injected through the `:clock` option for deterministic
  testing.
  """

  import Bitwise

  @typedoc "A keyring mapping binary key ids to binary signing secrets."
  @type keyring :: %{optional(binary()) => binary()}

  @mac_size 32

  @doc """
  Generate a URL-safe token for `payload`, signed with `keyring[active_kid]`.

  `keyring` is a `%{key_id => secret}` map, `active_kid` must be a key present
  in `keyring`, and `ttl_seconds` is a positive integer controlling how long
  the token stays valid. The signed region encodes the key id, the payload and
  the issue and expiry timestamps, protected by an HMAC-SHA256 signature.

  Options:

    * `:clock` — a zero-arity function returning a Unix epoch second, used as
      a test seam. Defaults to `System.os_time(:second)`.
  """
  @spec generate(term(), keyring(), binary(), pos_integer(), keyword()) :: binary()
  def generate(payload, keyring, active_kid, ttl_seconds, opts \\ [])
      when is_binary(active_kid) and is_integer(ttl_seconds) and ttl_seconds > 0 do
    secret = Map.fetch!(keyring, active_kid)
    issued_at = now(opts)
    expires_at = issued_at + ttl_seconds
    payload_bin = :erlang.term_to_binary(payload)

    signed =
      <<byte_size(active_kid)::unsigned-big-16, active_kid::binary, issued_at::unsigned-big-64,
        expires_at::unsigned-big-64, payload_bin::binary>>

    mac = :crypto.mac(:hmac, :sha256, secret, signed)
    Base.url_encode64(signed <> mac, padding: false)
  end

  @doc """
  Decode and validate `token` against `keyring`.

  Returns `{:ok, payload}` when the embedded key id is known, the signature is
  valid, and the token has not expired. The checks run in a fixed order:
  base64 decode, split off the trailing MAC, structural parse, key-id lookup,
  HMAC verification, expiry check, payload deserialization.

  `token` may be any term; anything that is not a well-formed binary token
  yields `{:error, :malformed}`.

  Error results:

    * `{:error, :malformed}` — any failure before the key-id lookup (bad
      base64, too short, header that doesn't match the bytes, non-binary
      input) or a post-HMAC deserialization failure.
    * `{:error, :unknown_key}` — the key id is not in `keyring`.
    * `{:error, :invalid_signature}` — the HMAC does not match.
    * `{:error, :expired}` — a known-key, valid-signature token whose
      `expires_at` is `<=` the current time.

  Options:

    * `:clock` — a zero-arity function returning a Unix epoch second, used as
      a test seam. Defaults to `System.os_time(:second)`.
  """
  @spec verify(term(), keyring(), keyword()) ::
          {:ok, term()}
          | {:error, :expired | :invalid_signature | :unknown_key | :malformed}
  def verify(token, keyring, opts \\ [])

  def verify(token, keyring, opts) when is_binary(token) do
    with {:ok, decoded} <- decode(token),
         {:ok, signed, mac} <- split_mac(decoded),
         {:ok, kid, expires_at, payload_bin} <- parse(signed) do
      verify_key(keyring, kid, signed, mac, expires_at, payload_bin, opts)
    else
      _ -> {:error, :malformed}
    end
  end

  def verify(_token, _keyring, _opts), do: {:error, :malformed}

  @spec decode(binary()) :: {:ok, binary()} | :error
  defp decode(token), do: Base.url_decode64(token, padding: false)

  @spec split_mac(binary()) :: {:ok, binary(), binary()} | :error
  defp split_mac(bin) do
    size = byte_size(bin)

    if size >= @mac_size do
      signed = binary_part(bin, 0, size - @mac_size)
      mac = binary_part(bin, size - @mac_size, @mac_size)
      {:ok, signed, mac}
    else
      :error
    end
  end

  @spec parse(binary()) :: {:ok, binary(), non_neg_integer(), binary()} | :error
  defp parse(signed) do
    with <<kid_len::unsigned-big-16, rest::binary>> <- signed,
         <<kid::binary-size(kid_len), _issued_at::unsigned-big-64, expires_at::unsigned-big-64,
           payload_bin::binary>> <- rest do
      {:ok, kid, expires_at, payload_bin}
    else
      _ -> :error
    end
  end

  @spec verify_key(
          keyring(),
          binary(),
          binary(),
          binary(),
          non_neg_integer(),
          binary(),
          keyword()
        ) :: {:ok, term()} | {:error, :expired | :invalid_signature | :unknown_key | :malformed}
  defp verify_key(keyring, kid, signed, mac, expires_at, payload_bin, opts) do
    case Map.fetch(keyring, kid) do
      :error ->
        {:error, :unknown_key}

      {:ok, secret} ->
        expected = :crypto.mac(:hmac, :sha256, secret, signed)

        cond do
          not secure_compare(mac, expected) -> {:error, :invalid_signature}
          now(opts) >= expires_at -> {:error, :expired}
          true -> deserialize(payload_bin)
        end
    end
  end

  @spec deserialize(binary()) :: {:ok, term()} | {:error, :malformed}
  defp deserialize(bin) do
    {:ok, :erlang.binary_to_term(bin, [:safe])}
  rescue
    ArgumentError -> {:error, :malformed}
  end

  @spec now(keyword()) :: integer()
  defp now(opts) do
    case Keyword.get(opts, :clock) do
      nil -> System.os_time(:second)
      fun when is_function(fun, 0) -> fun.()
    end
  end

  @spec secure_compare(binary(), binary()) :: boolean()
  defp secure_compare(a, b) when byte_size(a) == byte_size(b) do
    secure_compare(a, b, 0) == 0
  end

  defp secure_compare(_a, _b), do: false

  @spec secure_compare(binary(), binary(), non_neg_integer()) :: non_neg_integer()
  defp secure_compare(<<x, a::binary>>, <<y, b::binary>>, acc) do
    secure_compare(a, b, bor(acc, bxor(x, y)))
  end

  defp secure_compare(<<>>, <<>>, acc), do: acc
end
