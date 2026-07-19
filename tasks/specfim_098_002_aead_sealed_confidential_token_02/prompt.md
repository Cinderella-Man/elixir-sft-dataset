# Write the missing @spec

Below is a complete, working module — except that the `@spec` for
`seal/4` has been removed; its place is marked `# TODO: @spec`.
Write exactly that typespec: one `@spec` attribute for `seal/4`,
consistent with the function's arguments, guards, and every return shape
the implementation can produce. Change nothing else.

## The module with the `@spec` for `seal/4` missing

```elixir
defmodule SealedToken do
  @moduledoc """
  Confidential, expiring, stateless tokens backed by authenticated encryption.

  A `SealedToken` carries an encrypted Elixir term along with an issue and an
  expiration timestamp. Encryption uses AES-256-GCM, which provides both
  secrecy (an observer without the key cannot read the payload) and integrity
  (any tampering is detected). No database or persistent state is required:
  everything needed to open a token travels inside the token itself.

  The wire format, before base64 URL encoding, is the concatenation of:

    * a fresh random 12-byte nonce,
    * the 64-bit issued-at Unix timestamp,
    * the 64-bit expires-at Unix timestamp,
    * the 16-byte GCM authentication tag,
    * the encrypted payload (ciphertext).

  The two timestamps are supplied as GCM additional authenticated data (AAD),
  so they are authenticated by the tag but are not themselves encrypted and
  cannot be altered independently of the ciphertext.
  """

  @cipher :aes_256_gcm
  @nonce_size 12
  @tag_size 16

  @typedoc "A URL-safe, base64-encoded sealed token."
  @type token :: binary()

  @doc """
  Seals `payload` into a confidential, expiring, URL-safe token.

  `key` must be a 32-byte binary AES-256 key and `ttl_seconds` a positive
  integer number of seconds until expiry. A fresh random nonce is generated on
  every call, so sealing the same payload twice yields two different tokens;
  both open successfully.

  The `:clock` option, a zero-arity function returning a Unix epoch second, is
  a test seam for deterministic timing. When omitted, `System.os_time/1` is
  used.
  """
  # TODO: @spec
  def seal(payload, key, ttl_seconds, opts \\ [])
      when is_binary(key) and is_integer(ttl_seconds) and ttl_seconds > 0 do
    now = now(opts)
    issued_at = now
    expires_at = now + ttl_seconds

    nonce = :crypto.strong_rand_bytes(@nonce_size)
    plaintext = :erlang.term_to_binary(payload)
    aad = <<issued_at::64, expires_at::64>>

    {ciphertext, tag} =
      :crypto.crypto_one_time_aead(@cipher, key, nonce, plaintext, aad, true)

    binary =
      <<nonce::binary-size(@nonce_size), issued_at::64, expires_at::64,
        tag::binary-size(@tag_size), ciphertext::binary>>

    Base.url_encode64(binary, padding: false)
  end

  @doc """
  Opens a sealed `token`, authenticating, decrypting, and validating it.

  Returns `{:ok, payload}` when the token authenticates and has not expired.
  Returns `{:error, :expired}` when it authenticates but the current time is at
  or past its expiration (strict validity: `now < expires_at`). Returns
  `{:error, :invalid}` when it parses structurally but fails authenticated
  decryption (wrong key, tampered ciphertext, nonce, or timestamps). Returns
  `{:error, :malformed}` when it cannot be structurally decoded at all.

  Authentication is always checked before expiry, so a token opened with the
  wrong key that is also past its expiry returns `:invalid`, never `:expired`.

  The `:clock` option behaves as documented on `seal/4`.
  """
  @spec open(token(), binary(), keyword()) ::
          {:ok, term()} | {:error, :expired | :invalid | :malformed}
  def open(token, key, opts \\ []) do
    with true <- is_binary(token),
         {:ok, binary} <- decode(token),
         {:ok, nonce, issued_at, expires_at, tag, ciphertext} <- parse(binary) do
      decrypt_and_validate(key, nonce, issued_at, expires_at, tag, ciphertext, opts)
    else
      _ -> {:error, :malformed}
    end
  end

  @spec decode(binary()) :: {:ok, binary()} | :error
  defp decode(token), do: Base.url_decode64(token, padding: false)

  @spec parse(binary()) ::
          {:ok, binary(), non_neg_integer(), non_neg_integer(), binary(), binary()}
          | :error
  defp parse(
         <<nonce::binary-size(@nonce_size), issued_at::64, expires_at::64,
           tag::binary-size(@tag_size), ciphertext::binary>>
       ) do
    {:ok, nonce, issued_at, expires_at, tag, ciphertext}
  end

  defp parse(_binary), do: :error

  @spec decrypt_and_validate(
          binary(),
          binary(),
          non_neg_integer(),
          non_neg_integer(),
          binary(),
          binary(),
          keyword()
        ) :: {:ok, term()} | {:error, :expired | :invalid | :malformed}
  defp decrypt_and_validate(key, nonce, issued_at, expires_at, tag, ciphertext, opts) do
    aad = <<issued_at::64, expires_at::64>>

    case :crypto.crypto_one_time_aead(@cipher, key, nonce, ciphertext, aad, tag, false) do
      :error ->
        {:error, :invalid}

      plaintext when is_binary(plaintext) ->
        validate_and_deserialize(plaintext, expires_at, opts)
    end
  end

  @spec validate_and_deserialize(binary(), non_neg_integer(), keyword()) ::
          {:ok, term()} | {:error, :expired | :malformed}
  defp validate_and_deserialize(plaintext, expires_at, opts) do
    if now(opts) < expires_at do
      deserialize(plaintext)
    else
      {:error, :expired}
    end
  end

  @spec deserialize(binary()) :: {:ok, term()} | {:error, :malformed}
  defp deserialize(plaintext) do
    {:ok, :erlang.binary_to_term(plaintext, [:safe])}
  rescue
    ArgumentError -> {:error, :malformed}
  end

  @spec now(keyword()) :: integer()
  defp now(opts) do
    case Keyword.get(opts, :clock) do
      fun when is_function(fun, 0) -> fun.()
      _ -> System.os_time(:second)
    end
  end
end
```

Give me only the `@spec` attribute — the attribute alone (however many
lines it spans), not the whole module.
