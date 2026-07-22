defmodule SealedToken do
  @moduledoc """
  Encrypted, expiring, stateless tokens built on authenticated encryption.

  A `SealedToken` seals an arbitrary Elixir term together with its issue and
  expiration timestamps into a single AES-256-GCM ciphertext, then encodes the
  result as a URL-safe, unpadded Base64 string. Because the payload lives
  inside the ciphertext, an observer holding the token but not the 32-byte key
  learns nothing about the payload: confidentiality and integrity both derive
  from the same AEAD primitive.

  The wire format of the decoded token is:

      <<nonce::binary-12, tag::binary-16, ciphertext::binary>>

  and the authenticated plaintext inside the ciphertext is:

      <<issued_at::signed-64, expires_at::signed-64, payload_term::binary>>

  Each `seal/4` call draws a fresh random 12-byte nonce, so sealing the same
  payload twice yields two different tokens. No database or persistent state is
  involved — validity is entirely self-contained.
  """

  @nonce_size 12
  @tag_size 16
  @min_size @nonce_size + @tag_size

  @doc """
  Seal `payload` into a URL-safe encrypted token valid for `ttl_seconds`.

  `key` must be a 32-byte binary (an AES-256 key) and `ttl_seconds` a positive
  integer. The returned token encrypts the payload alongside its issue and
  expiration timestamps under a fresh random nonce.

  The only recognized option is `:clock`, a zero-arity function returning a Unix
  epoch second; it defaults to `System.os_time(:second)` and exists purely as a
  test seam for deterministic expiry.
  """
  @spec seal(term(), binary(), pos_integer(), keyword()) :: binary()
  def seal(payload, key, ttl_seconds, opts \\ [])
      when is_binary(key) and is_integer(ttl_seconds) and ttl_seconds > 0 do
    clock = clock_fun(opts)
    issued_at = clock.()
    expires_at = issued_at + ttl_seconds
    payload_bin = :erlang.term_to_binary(payload)
    plaintext = <<issued_at::signed-64, expires_at::signed-64, payload_bin::binary>>
    nonce = :crypto.strong_rand_bytes(@nonce_size)

    {ciphertext, tag} =
      :crypto.crypto_one_time_aead(:aes_256_gcm, key, nonce, plaintext, <<>>, true)

    Base.url_encode64(nonce <> tag <> ciphertext, padding: false)
  end

  @doc """
  Decrypt and validate `token`, returning `{:ok, payload}` when it is genuine
  and unexpired.

  Returns `{:error, :expired}` when the token authenticates but the current
  time is at or past `expires_at`, `{:error, :invalid}` when a structurally
  present token fails authentication (wrong key or tampered bytes), and
  `{:error, :malformed}` for anything that cannot even be structurally read:
  bad Base64, a decoded length below #{@min_size} bytes, non-binary input, or a
  post-decrypt parse/deserialization failure.

  The only recognized option is `:clock`; see `seal/4`.
  """
  @spec open(binary(), binary(), keyword()) ::
          {:ok, term()} | {:error, :expired | :invalid | :malformed}
  def open(token, key, opts \\ [])

  def open(token, key, opts) when is_binary(token) do
    clock = clock_fun(opts)

    with {:ok, decoded} <- decode(token),
         {:ok, nonce, tag, ciphertext} <- split(decoded),
         {:ok, plaintext} <- decrypt(key, nonce, tag, ciphertext),
         {:ok, expires_at, payload_bin} <- parse(plaintext),
         :ok <- check_expiry(expires_at, clock.()),
         {:ok, payload} <- deserialize(payload_bin) do
      {:ok, payload}
    end
  end

  def open(_token, _key, _opts), do: {:error, :malformed}

  @spec clock_fun(keyword()) :: (-> integer())
  defp clock_fun(opts) do
    Keyword.get(opts, :clock, fn -> System.os_time(:second) end)
  end

  @spec decode(binary()) :: {:ok, binary()} | {:error, :malformed}
  defp decode(token) do
    case Base.url_decode64(token, padding: false) do
      {:ok, decoded} -> {:ok, decoded}
      :error -> {:error, :malformed}
    end
  end

  @spec split(binary()) ::
          {:ok, binary(), binary(), binary()} | {:error, :malformed}
  defp split(<<nonce::binary-size(@nonce_size), tag::binary-size(@tag_size), ciphertext::binary>>) do
    {:ok, nonce, tag, ciphertext}
  end

  defp split(_decoded), do: {:error, :malformed}

  @spec decrypt(binary(), binary(), binary(), binary()) ::
          {:ok, binary()} | {:error, :invalid}
  defp decrypt(key, nonce, tag, ciphertext) do
    case :crypto.crypto_one_time_aead(:aes_256_gcm, key, nonce, ciphertext, <<>>, tag, false) do
      plaintext when is_binary(plaintext) -> {:ok, plaintext}
      :error -> {:error, :invalid}
    end
  rescue
    _error -> {:error, :invalid}
  end

  @spec parse(binary()) :: {:ok, integer(), binary()} | {:error, :malformed}
  defp parse(<<_issued_at::signed-64, expires_at::signed-64, payload_bin::binary>>) do
    {:ok, expires_at, payload_bin}
  end

  defp parse(_plaintext), do: {:error, :malformed}

  @spec check_expiry(integer(), integer()) :: :ok | {:error, :expired}
  defp check_expiry(expires_at, now) when now < expires_at, do: :ok
  defp check_expiry(_expires_at, _now), do: {:error, :expired}

  @spec deserialize(binary()) :: {:ok, term()} | {:error, :malformed}
  defp deserialize(payload_bin) do
    {:ok, :erlang.binary_to_term(payload_bin, [:safe])}
  rescue
    _error -> {:error, :malformed}
  end
end
