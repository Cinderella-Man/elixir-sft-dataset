defmodule RotatingToken do
  @moduledoc """
  Generation and verification of signed, expiring tokens against a *keyring*
  of multiple secrets.

  A token is a self-contained, URL-safe binary. It carries everything needed
  to verify it — the payload, the issue timestamp, the expiration timestamp,
  the id of the key that signed it, and an HMAC-SHA256 signature over all of
  those fields — except the secrets themselves, which the caller supplies as a
  keyring (`%{key_id => secret}`).

  Because the signing key id is embedded in the token *and* covered by the MAC,
  verification can select the correct secret from the id inside the token. This
  is what makes key rotation work: after adding a new key to the keyring and
  signing fresh tokens with it, tokens signed with older keys still verify for
  as long as their key ids remain in the keyring.

  ## Token layout

  The signed region is framed as:

      <<issued_at::64, expires_at::64, key_id_len::16, key_id::binary,
        payload_len::32, payload::binary>>

  The full token before encoding is `signed_region <> hmac` where `hmac` is a
  32-byte HMAC-SHA256 over `signed_region`. The result is encoded with
  `Base.url_encode64/2` using `padding: false`.

  ## Options

  Both public functions accept an optional keyword list. The only recognized
  key is `:clock`, a zero-arity function returning a Unix epoch second. It is a
  test seam for deterministic expiry testing; when omitted, the current time is
  read from `System.os_time(:second)`.
  """

  import Bitwise

  @mac_size 32

  @typedoc "A keyring mapping binary key ids to binary signing secrets."
  @type keyring :: %{optional(binary()) => binary()}

  @typedoc "Reasons a token can fail verification."
  @type error :: :unknown_key | :invalid_signature | :expired | :malformed

  @doc """
  Generate a URL-safe signed token.

  `payload` is any Elixir term. `keyring` maps binary key ids to binary
  secrets. `active_key_id` selects the secret used to sign this token and must
  be present in `keyring`. `ttl_seconds` is a positive integer number of
  seconds until the token expires.

  Returns the encoded token as a URL-safe binary. Raises `KeyError` if
  `active_key_id` is not present in `keyring`.
  """
  @spec generate(term(), keyring(), binary(), pos_integer(), keyword()) :: binary()
  def generate(payload, keyring, active_key_id, ttl_seconds, opts \\ [])
      when is_map(keyring) and is_binary(active_key_id) and is_integer(ttl_seconds) and
             ttl_seconds > 0 do
    clock = Keyword.get(opts, :clock, &default_clock/0)
    secret = Map.fetch!(keyring, active_key_id)

    issued_at = clock.()
    expires_at = issued_at + ttl_seconds
    payload_bin = :erlang.term_to_binary(payload)

    region = build_region(issued_at, expires_at, active_key_id, payload_bin)
    mac = :crypto.mac(:hmac, :sha256, secret, region)

    Base.url_encode64(region <> mac, padding: false)
  end

  @doc """
  Decode and validate a token against `keyring`.

  Verification proceeds in a fixed order: base64 decode, split off the trailing
  32-byte MAC, structurally parse the header, look the embedded key id up in
  `keyring`, verify the HMAC in constant time, check expiry, then deserialize
  the payload.

  `token` and `keyring` may be any term: anything that is not a binary token
  paired with a map keyring is treated as structurally malformed.

  Returns:

    * `{:ok, payload}` when the key id is known, the signature is valid, and the
      token has not expired.
    * `{:error, :unknown_key}` when the token parses but its key id is absent
      from `keyring`.
    * `{:error, :invalid_signature}` when the key id is known but the HMAC does
      not match.
    * `{:error, :expired}` when the signature is valid but the current time is
      at or past `expires_at` (strict `<` validity check).
    * `{:error, :malformed}` for anything that cannot be decoded or parsed, and
      for a post-HMAC payload deserialization failure.
  """
  @spec verify(term(), term(), keyword()) :: {:ok, term()} | {:error, error()}
  def verify(token, keyring, opts \\ [])

  def verify(token, keyring, opts) when is_binary(token) and is_map(keyring) do
    clock = Keyword.get(opts, :clock, &default_clock/0)

    with {:ok, raw} <- decode(token),
         {:ok, region, mac} <- split_mac(raw),
         {:ok, expires_at, key_id, payload_bin} <- parse(region) do
      verify_key(keyring, key_id, region, mac, expires_at, payload_bin, clock)
    else
      _ -> {:error, :malformed}
    end
  end

  def verify(_token, _keyring, _opts), do: {:error, :malformed}

  # --- Internal helpers ----------------------------------------------------

  @spec build_region(non_neg_integer(), non_neg_integer(), binary(), binary()) :: binary()
  defp build_region(issued_at, expires_at, key_id, payload_bin) do
    <<issued_at::unsigned-big-integer-size(64), expires_at::unsigned-big-integer-size(64),
      byte_size(key_id)::unsigned-big-integer-size(16), key_id::binary,
      byte_size(payload_bin)::unsigned-big-integer-size(32), payload_bin::binary>>
  end

  @spec decode(binary()) :: {:ok, binary()} | :error
  defp decode(token) do
    case Base.url_decode64(token, padding: false) do
      {:ok, raw} -> {:ok, raw}
      :error -> :error
    end
  end

  @spec split_mac(binary()) :: {:ok, binary(), binary()} | :error
  defp split_mac(raw) when byte_size(raw) >= @mac_size do
    region_size = byte_size(raw) - @mac_size
    <<region::binary-size(region_size), mac::binary-size(@mac_size)>> = raw
    {:ok, region, mac}
  end

  defp split_mac(_raw), do: :error

  @spec parse(binary()) :: {:ok, non_neg_integer(), binary(), binary()} | :error
  defp parse(region) do
    case region do
      <<_issued_at::unsigned-big-integer-size(64), expires_at::unsigned-big-integer-size(64),
        klen::unsigned-big-integer-size(16), key_id::binary-size(klen),
        plen::unsigned-big-integer-size(32), payload_bin::binary-size(plen)>> ->
        {:ok, expires_at, key_id, payload_bin}

      _other ->
        :error
    end
  end

  @spec verify_key(
          keyring(),
          binary(),
          binary(),
          binary(),
          non_neg_integer(),
          binary(),
          (-> integer())
        ) :: {:ok, term()} | {:error, error()}
  defp verify_key(keyring, key_id, region, mac, expires_at, payload_bin, clock) do
    case Map.fetch(keyring, key_id) do
      :error ->
        {:error, :unknown_key}

      {:ok, secret} ->
        expected = :crypto.mac(:hmac, :sha256, secret, region)
        check_signature(expected, mac, expires_at, payload_bin, clock)
    end
  end

  @spec check_signature(binary(), binary(), non_neg_integer(), binary(), (-> integer())) ::
          {:ok, term()} | {:error, error()}
  defp check_signature(expected, mac, expires_at, payload_bin, clock) do
    if constant_time_equal?(expected, mac) do
      check_expiry(expires_at, payload_bin, clock)
    else
      {:error, :invalid_signature}
    end
  end

  @spec check_expiry(non_neg_integer(), binary(), (-> integer())) ::
          {:ok, term()} | {:error, error()}
  defp check_expiry(expires_at, payload_bin, clock) do
    if clock.() < expires_at do
      deserialize(payload_bin)
    else
      {:error, :expired}
    end
  end

  @spec deserialize(binary()) :: {:ok, term()} | {:error, :malformed}
  defp deserialize(payload_bin) do
    {:ok, :erlang.binary_to_term(payload_bin, [:safe])}
  rescue
    ArgumentError -> {:error, :malformed}
  end

  @spec constant_time_equal?(binary(), binary()) :: boolean()
  defp constant_time_equal?(a, b) when byte_size(a) == byte_size(b) do
    acc =
      a
      |> :binary.bin_to_list()
      |> Enum.zip(:binary.bin_to_list(b))
      |> Enum.reduce(0, fn {x, y}, acc -> bor(acc, bxor(x, y)) end)

    acc === 0
  end

  defp constant_time_equal?(_a, _b), do: false

  @spec default_clock() :: integer()
  defp default_clock, do: System.os_time(:second)
end
