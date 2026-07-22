defmodule SealedToken do
  @moduledoc """
  Stateless, encrypted, expiring tokens built on AES-256-GCM.

  A sealed token is a self-contained binary that carries everything needed to open it,
  so no database or server-side session store is required. Unlike a merely *signed*
  token, the payload is **confidential**: an observer without the key cannot read it.
  Authenticated encryption (AES-256-GCM) provides secrecy and integrity in a single
  operation, making the token tamper-evident as well.

  ## Wire format

  The token is the URL-safe, unpadded Base64 encoding of:

      nonce (12 bytes) || issued_at (64-bit big-endian) || expires_at (64-bit big-endian)
        || tag (16 bytes) || ciphertext (variable)

  The two timestamps travel in the clear but are supplied to AES-GCM as additional
  authenticated data (AAD), so they are covered by the authentication tag and cannot be
  altered independently of the ciphertext.

  ## Validation order

  `open/3` performs its checks in exactly this order:

    1. Base64 decode
    2. structural parse (nonce, timestamps, tag)
    3. authenticated decryption
    4. expiry check
    5. payload deserialization

  Structural failures before authenticated decryption yield `{:error, :malformed}`.
  Authentication failures yield `{:error, :invalid}`. Because authentication precedes
  the expiry check, a token opened with the wrong key that is *also* past its expiry
  returns `{:error, :invalid}` — never `{:error, :expired}`.

  ## Examples

      iex> key = :crypto.strong_rand_bytes(32)
      iex> token = SealedToken.seal(%{user_id: 7}, key, 60)
      iex> SealedToken.open(token, key)
      {:ok, %{user_id: 7}}

  """

  @cipher :aes_256_gcm

  @nonce_size 12
  @tag_size 16
  @timestamp_bits 64
  @timestamp_size 8
  @aad_size 2 * @timestamp_size

  @minimum_size @nonce_size + @aad_size + @tag_size

  @typedoc "A 32-byte AES-256 encryption key."
  @type key :: <<_::256>>

  @typedoc "Options accepted by `seal/4` and `open/3`."
  @type opts :: [clock: (-> integer())]

  @typedoc "Reasons `open/3` can refuse a token."
  @type error :: :expired | :invalid | :malformed

  @doc """
  Seals `payload` into a URL-safe token that expires `ttl_seconds` from now.

  `payload` may be any Elixir term, `key` must be a 32-byte binary, and `ttl_seconds`
  must be a positive integer.

  A fresh random 12-byte nonce is drawn on every call, so sealing the same payload twice
  produces two different tokens; both open successfully.

  ## Options

    * `:clock` — zero-arity function returning a Unix epoch second. Defaults to
      `System.os_time(:second)`. This is a test seam; the default applies in production.

  ## Examples

      iex> key = :crypto.strong_rand_bytes(32)
      iex> token = SealedToken.seal("hello", key, 300)
      iex> SealedToken.open(token, key)
      {:ok, "hello"}

  """
  @spec seal(term(), key(), pos_integer(), opts()) :: binary()
  def seal(payload, key, ttl_seconds, opts \\ [])
      when is_binary(key) and byte_size(key) == 32 and is_integer(ttl_seconds) and
             ttl_seconds > 0 and is_list(opts) do
    now = now(opts)
    expires_at = now + ttl_seconds

    nonce = :crypto.strong_rand_bytes(@nonce_size)
    aad = <<now::big-signed-integer-size(@timestamp_bits),
            expires_at::big-signed-integer-size(@timestamp_bits)>>

    plaintext = :erlang.term_to_binary(payload)

    {ciphertext, tag} =
      :crypto.crypto_one_time_aead(@cipher, key, nonce, plaintext, aad, @tag_size, true)

    Base.url_encode64(nonce <> aad <> tag <> ciphertext, padding: false)
  end

  @doc """
  Decodes, authenticates, decrypts and validates `token`.

  Returns `{:ok, payload}` when the token authenticates under `key` and has not expired.

  Returns:

    * `{:error, :expired}` — the token authenticates but the current time is at or past
      `expires_at` (the validity check is strict: `now < expires_at`).
    * `{:error, :invalid}` — the token parses structurally but fails authenticated
      decryption: wrong key, tampered ciphertext, tampered nonce, or tampered timestamps.
    * `{:error, :malformed}` — the token cannot be structurally decoded at all: bad
      base64, too short to hold a nonce, timestamps and tag, non-binary input, or a
      payload that fails safe deserialization after decryption.

  ## Options

    * `:clock` — zero-arity function returning a Unix epoch second. Defaults to
      `System.os_time(:second)`.

  ## Examples

      iex> key = :crypto.strong_rand_bytes(32)
      iex> token = SealedToken.seal(:secret, key, 60)
      iex> SealedToken.open(token, key, clock: fn -> System.os_time(:second) + 120 end)
      {:error, :expired}

  """
  @spec open(binary(), key(), opts()) :: {:ok, term()} | {:error, error()}
  def open(token, key, opts \\ [])

  def open(token, key, opts)
      when is_binary(token) and is_binary(key) and byte_size(key) == 32 and is_list(opts) do
    with {:ok, raw} <- decode(token),
         {:ok, nonce, aad, expires_at, tag, ciphertext} <- parse(raw),
         {:ok, plaintext} <- decrypt(key, nonce, aad, tag, ciphertext),
         :ok <- check_expiry(expires_at, opts) do
      deserialize(plaintext)
    end
  end

  def open(_token, _key, _opts), do: {:error, :malformed}

  # -- internals ------------------------------------------------------------------

  @spec decode(binary()) :: {:ok, binary()} | {:error, :malformed}
  defp decode(token) do
    case Base.url_decode64(token, padding: false) do
      {:ok, raw} -> {:ok, raw}
      :error -> {:error, :malformed}
    end
  end

  @spec parse(binary()) ::
          {:ok, binary(), binary(), integer(), binary(), binary()} | {:error, :malformed}
  defp parse(raw) when byte_size(raw) >= @minimum_size do
    <<nonce::binary-size(@nonce_size),
      aad::binary-size(@aad_size),
      tag::binary-size(@tag_size),
      ciphertext::binary>> = raw

    <<_issued_at::big-signed-integer-size(@timestamp_bits),
      expires_at::big-signed-integer-size(@timestamp_bits)>> = aad

    {:ok, nonce, aad, expires_at, tag, ciphertext}
  end

  defp parse(_raw), do: {:error, :malformed}

  @spec decrypt(key(), binary(), binary(), binary(), binary()) ::
          {:ok, binary()} | {:error, :invalid}
  defp decrypt(key, nonce, aad, tag, ciphertext) do
    case :crypto.crypto_one_time_aead(@cipher, key, nonce, ciphertext, aad, tag, false) do
      plaintext when is_binary(plaintext) -> {:ok, plaintext}
      :error -> {:error, :invalid}
    end
  rescue
    _ -> {:error, :invalid}
  end

  @spec check_expiry(integer(), opts()) :: :ok | {:error, :expired}
  defp check_expiry(expires_at, opts) do
    if now(opts) < expires_at, do: :ok, else: {:error, :expired}
  end

  @spec deserialize(binary()) :: {:ok, term()} | {:error, :malformed}
  defp deserialize(plaintext) do
    {:ok, :erlang.binary_to_term(plaintext, [:safe])}
  rescue
    _ -> {:error, :malformed}
  end

  @spec now(opts()) :: integer()
  defp now(opts) do
    case Keyword.get(opts, :clock) do
      nil -> System.os_time(:second)
      clock when is_function(clock, 0) -> clock.()
    end
  end
end