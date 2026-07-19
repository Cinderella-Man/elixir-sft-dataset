# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `deserialize` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

Write me an Elixir module called `SealedToken` that produces and opens
*encrypted*, expiring tokens without any database or persistent state.
Unlike a plain signed token, the payload here must be **confidential** —
an observer who does not hold the key must not be able to read it — and
tamper-evident at the same time. Use authenticated encryption (AES-256-GCM)
so that a single operation gives you both secrecy and integrity.

I need these two functions in the public API:

- `SealedToken.seal(payload, key, ttl_seconds, opts \\ [])` where
  `payload` is any Elixir term, `key` is a 32-byte binary encryption key,
  and `ttl_seconds` is a positive integer. It must return a URL-safe
  binary token (no padding issues, safe to embed in URLs or headers) that
  carries a fresh random 12-byte nonce, the issue timestamp, the
  expiration timestamp, the GCM authentication tag, and the encrypted
  payload. Because a fresh random nonce is chosen on every call, sealing
  the same payload twice yields two *different* tokens; both must open
  successfully.

- `SealedToken.open(token, key, opts \\ [])` which decodes, authenticates,
  decrypts, and validates the token. Return `{:ok, payload}` if the token
  authenticates and has not expired. Return `{:error, :expired}` if the
  token authenticates but the current time is at or past the expiration.
  Return `{:error, :invalid}` if the token parses structurally but fails
  authenticated decryption (wrong key, tampered ciphertext, tampered
  nonce, or tampered timestamps — the timestamps are part of the
  authenticated data, so they cannot be altered independently). Return
  `{:error, :malformed}` for anything that cannot be structurally decoded
  at all: bad base64, too short to contain a nonce + timestamps + tag,
  non-binary input, and so on.

Both functions take an optional `opts` keyword. The only recognized key
is `:clock`, a zero-arity function returning a Unix epoch second. When
omitted, the current time is read from `System.os_time(:second)`. This is
purely a test seam for deterministic expiry testing — in production the
default applies.

The check order inside `open` is exactly: base64 decode → structural
parse (peel off the 12-byte nonce, the two 64-bit timestamps, and the
16-byte tag) → authenticated decryption → expiry check → payload
deserialization. Any structural failure before authenticated decryption
yields `:malformed`. An authentication failure yields `:invalid`.
Authentication is therefore always checked *before* expiry, so a token
opened with the wrong key that also happens to be past its expiry returns
`:invalid`, never `:expired`. A post-decryption expiry failure yields
`:expired`. A post-decryption deserialization failure yields `:malformed`.
A token whose `expires_at` equals the current time is already expired (use
strict `<` on the validity check, not `<=`).

Implementation requirements:

- Use `:crypto.crypto_one_time_aead/6,7` with the `:aes_256_gcm` cipher.
- The two timestamps must be passed as the AAD (additional authenticated
  data) so they are covered by the tag without being encrypted.
- Use `Base.url_encode64/2` with `padding: false` so the output is
  URL-safe without `=` characters.
- Generate the nonce with `:crypto.strong_rand_bytes/1`.
- Deserialize the payload with `:erlang.binary_to_term/2` using the
  `[:safe]` option.
- Do not use any external dependencies — only the Elixir standard library
  and OTP.

Give me the complete module in a single file.

## The module with `deserialize` missing

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
  @spec seal(term(), binary(), pos_integer(), keyword()) :: token()
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

  defp deserialize(plaintext) do
    # TODO
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

Give me only the complete implementation of `deserialize` (including any
`@doc`/`@spec`/`@impl` lines that belong directly above it) — the
function alone, not the whole module.
