defmodule KeyringToken do
  @moduledoc """
  Self-contained, signed, expiring tokens backed by a *keyring* of named signing keys.

  A keyring is a plain map of `%{key_id => secret}` where both the id and the secret are
  binaries. Every token embeds the id of the key that signed it, so a verifier can look the
  secret up at verification time. That indirection is what makes key rotation possible: while
  both the old and the new secret live in the keyring, tokens signed with either one continue
  to verify. Once the old secret is dropped, tokens signed with it report
  `{:error, :unknown_key}`.

  ## Wire format

  A token is `Base.url_encode64(body <> mac, padding: false)` where:

      body = <<key_id_len::16, key_id::binary, issued_at::64, expires_at::64,
               payload_len::32, payload::binary>>
      mac  = :crypto.mac(:hmac, :sha256, secret, body)   # 32 bytes

  The MAC covers the entire body, including the length prefixes and the key id, so no field can
  be tampered with independently.

  ## Time

  Both public functions accept an optional `opts` keyword list whose only recognized key is
  `:clock`, a zero-arity function returning a Unix epoch second. It exists purely as a test seam
  for deterministic expiry testing; when omitted, `System.os_time(:second)` is used.
  """

  @mac_size 32
  @hash :sha256

  @type keyring :: %{optional(binary()) => binary()}
  @type opts :: [clock: (-> integer())]
  @type error ::
          :malformed
          | :unknown_key
          | :invalid_signature
          | :expired

  @doc """
  Builds a signed, URL-safe token for `payload`.

  `keyring` is a `%{key_id => secret}` map, `key_id` names the secret to sign with, and
  `ttl_seconds` is a positive integer number of seconds the token stays valid for. The returned
  binary encodes the payload, the key id, the issue time and the expiry time, all covered by an
  HMAC-SHA256 signature.

  Raises `ArgumentError` if `key_id` is not present in `keyring`.

  ## Examples

      iex> keyring = %{"k1" => "s3cret"}
      iex> token = KeyringToken.generate(%{user: 1}, keyring, "k1", 60)
      iex> KeyringToken.verify(token, keyring)
      {:ok, %{user: 1}}
  """
  @spec generate(term(), keyring(), binary(), pos_integer(), opts()) :: binary()
  def generate(payload, keyring, key_id, ttl_seconds, opts \\ [])
      when is_map(keyring) and is_binary(key_id) and is_integer(ttl_seconds) and ttl_seconds > 0 and
             is_list(opts) do
    secret =
      case Map.fetch(keyring, key_id) do
        {:ok, secret} when is_binary(secret) ->
          secret

        _other ->
          raise ArgumentError, "unknown key id #{inspect(key_id)} for the supplied keyring"
      end

    issued_at = now(opts)
    expires_at = issued_at + ttl_seconds
    payload_bytes = :erlang.term_to_binary(payload)

    body = encode_body(key_id, issued_at, expires_at, payload_bytes)
    mac = :crypto.mac(:hmac, @hash, secret, body)

    Base.url_encode64(body <> mac, padding: false)
  end

  @doc """
  Decodes and validates `token` against `keyring`.

  Checks run in this order: base64 decode, MAC split, structural parse, keyring lookup of the
  embedded key id, HMAC verification, expiry, payload deserialization.

  Returns:

    * `{:ok, payload}` — key known, signature valid, not expired.
    * `{:error, :unknown_key}` — parsed, but the embedded key id is not in `keyring`.
    * `{:error, :invalid_signature}` — key known, but the HMAC does not match.
    * `{:error, :expired}` — key known and signature valid, but `expires_at <= now`.
    * `{:error, :malformed}` — anything that cannot be decoded at all.

  ## Examples

      iex> keyring = %{"k1" => "s3cret"}
      iex> token = KeyringToken.generate(:hello, keyring, "k1", 60)
      iex> KeyringToken.verify(token, %{})
      {:error, :unknown_key}
  """
  @spec verify(term(), term(), opts()) :: {:ok, term()} | {:error, error()}
  def verify(token, keyring, opts \\ [])

  def verify(token, keyring, opts) when is_binary(token) and is_map(keyring) and is_list(opts) do
    with {:ok, raw} <- decode64(token),
         {:ok, body, mac} <- split_mac(raw),
         {:ok, key_id, issued_at, expires_at, payload_bytes} <- parse_body(body),
         {:ok, secret} <- fetch_key(keyring, key_id),
         :ok <- check_mac(secret, body, mac),
         :ok <- check_expiry(expires_at, opts) do
      deserialize(payload_bytes, issued_at)
    end
  end

  def verify(_token, _keyring, _opts), do: {:error, :malformed}

  # -- encoding helpers ------------------------------------------------------------------

  @spec encode_body(binary(), integer(), integer(), binary()) :: binary()
  defp encode_body(key_id, issued_at, expires_at, payload_bytes) do
    <<byte_size(key_id)::unsigned-big-integer-size(16), key_id::binary,
      issued_at::signed-big-integer-size(64), expires_at::signed-big-integer-size(64),
      byte_size(payload_bytes)::unsigned-big-integer-size(32), payload_bytes::binary>>
  end

  @spec decode64(binary()) :: {:ok, binary()} | {:error, :malformed}
  defp decode64(token) do
    case Base.url_decode64(token, padding: false) do
      {:ok, raw} -> {:ok, raw}
      :error -> {:error, :malformed}
    end
  end

  @spec split_mac(binary()) :: {:ok, binary(), binary()} | {:error, :malformed}
  defp split_mac(raw) when byte_size(raw) > @mac_size do
    body_size = byte_size(raw) - @mac_size
    <<body::binary-size(body_size), mac::binary-size(@mac_size)>> = raw
    {:ok, body, mac}
  end

  defp split_mac(_raw), do: {:error, :malformed}

  @spec parse_body(binary()) ::
          {:ok, binary(), integer(), integer(), binary()} | {:error, :malformed}
  defp parse_body(<<key_id_len::unsigned-big-integer-size(16), rest::binary>>)
       when key_id_len > 0 and byte_size(rest) >= key_id_len + 20 do
    <<key_id::binary-size(key_id_len), issued_at::signed-big-integer-size(64),
      expires_at::signed-big-integer-size(64), payload_len::unsigned-big-integer-size(32),
      payload_rest::binary>> = rest

    case payload_rest do
      <<payload_bytes::binary-size(payload_len)>> ->
        {:ok, key_id, issued_at, expires_at, payload_bytes}

      _mismatch ->
        {:error, :malformed}
    end
  end

  defp parse_body(_body), do: {:error, :malformed}

  # -- validation helpers ----------------------------------------------------------------

  @spec fetch_key(keyring(), binary()) :: {:ok, binary()} | {:error, :unknown_key}
  defp fetch_key(keyring, key_id) do
    case Map.fetch(keyring, key_id) do
      {:ok, secret} when is_binary(secret) -> {:ok, secret}
      _other -> {:error, :unknown_key}
    end
  end

  @spec check_mac(binary(), binary(), binary()) :: :ok | {:error, :invalid_signature}
  defp check_mac(secret, body, mac) do
    expected = :crypto.mac(:hmac, @hash, secret, body)

    if secure_compare(expected, mac) do
      :ok
    else
      {:error, :invalid_signature}
    end
  end

  @spec secure_compare(binary(), binary()) :: boolean()
  defp secure_compare(left, right) when byte_size(left) == byte_size(right) do
    left
    |> :binary.bin_to_list()
    |> Enum.zip(:binary.bin_to_list(right))
    |> Enum.reduce(0, fn {a, b}, acc -> Bitwise.bor(acc, Bitwise.bxor(a, b)) end)
    |> Kernel.===(0)
  end

  defp secure_compare(_left, _right), do: false

  @spec check_expiry(integer(), opts()) :: :ok | {:error, :expired}
  defp check_expiry(expires_at, opts) do
    if now(opts) < expires_at do
      :ok
    else
      {:error, :expired}
    end
  end

  @spec deserialize(binary(), integer()) :: {:ok, term()} | {:error, :malformed}
  defp deserialize(payload_bytes, _issued_at) do
    {:ok, :erlang.binary_to_term(payload_bytes, [:safe])}
  rescue
    ArgumentError -> {:error, :malformed}
  end

  @spec now(opts()) :: integer()
  defp now(opts) do
    case Keyword.get(opts, :clock) do
      nil -> System.os_time(:second)
      clock when is_function(clock, 0) -> clock.()
    end
  end
end
