# Complete the blanked test

You get a module and its ExUnit harness, minus the body of ONE `test` —
the `# TODO` marks the spot, and its name says what it must prove. Write
exactly that test so the harness passes against a correct implementation
of the module.

## Module under test

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

## Test harness — implement the `# TODO` test

```elixir
defmodule SealedTokenTest do
  use ExUnit.Case, async: false

  # --- Fake clock for deterministic expiry testing ---

  defmodule Clock do
    use Agent

    def start_link(initial \\ 0) do
      Agent.start_link(fn -> initial end, name: __MODULE__)
    end

    def now, do: Agent.get(__MODULE__, & &1)
    def advance(seconds), do: Agent.update(__MODULE__, &(&1 + seconds))
    def set(seconds), do: Agent.update(__MODULE__, fn _ -> seconds end)
  end

  # 32-byte keys (AES-256).
  @key String.duplicate("k", 32)
  @key_a String.duplicate("a", 32)
  @key_b String.duplicate("b", 32)

  defp seal(payload, key, ttl),
    do: SealedToken.seal(payload, key, ttl, clock: &Clock.now/0)

  defp open(token, key),
    do: SealedToken.open(token, key, clock: &Clock.now/0)

  setup do
    start_supervised!({Clock, 1_000_000})
    :ok
  end

  # -------------------------------------------------------
  # Basic round-trip
  # -------------------------------------------------------

  test "sealed token opens successfully" do
    token = seal(%{user_id: 42}, @key, 300)
    assert is_binary(token)
    assert {:ok, %{user_id: 42}} = open(token, @key)
  end

  test "payload is preserved exactly through round-trip" do
    payload = %{role: "admin", sub: "user:99", meta: [1, 2, 3]}
    token = seal(payload, @key, 60)
    assert {:ok, ^payload} = open(token, @key)
  end

  test "token is URL-safe (no +, /, or = characters)" do
    token = seal("hello", @key, 60)
    refute String.contains?(token, "+")
    refute String.contains?(token, "/")
    refute String.contains?(token, "=")
  end

  test "sealing the same payload twice yields different tokens (random nonce)" do
    t1 = seal("same", @key, 60)
    t2 = seal("same", @key, 60)
    refute t1 == t2
    assert {:ok, "same"} = open(t1, @key)
    assert {:ok, "same"} = open(t2, @key)
  end

  # -------------------------------------------------------
  # Expiry
  # -------------------------------------------------------

  test "token is valid just before expiry" do
    token = seal("data", @key, 100)
    Clock.advance(99)
    assert {:ok, "data"} = open(token, @key)
  end

  test "expired token returns :expired" do
    token = seal("data", @key, 100)
    Clock.advance(101)
    assert {:error, :expired} = open(token, @key)
  end

  test "token expires exactly at ttl boundary" do
    token = seal("data", @key, 50)
    Clock.advance(50)
    assert {:error, :expired} = open(token, @key)
  end

  # -------------------------------------------------------
  # Authentication
  # -------------------------------------------------------

  test "wrong key returns :invalid" do
    token = seal("payload", @key_a, 300)
    assert {:error, :invalid} = open(token, @key_b)
  end

  test "tampered token returns :invalid" do
    token = seal(%{role: "user"}, @key, 300)

    tampered =
      token
      |> String.graphemes()
      |> List.update_at(div(byte_size(token), 2), fn
        "A" -> "B"
        _ -> "A"
      end)
      |> Enum.join()

    assert {:error, :invalid} = open(tampered, @key)
  end

  test "authentication check takes precedence over expiry check" do
    token = seal("old", @key_a, 1)
    Clock.advance(200)
    # Expired, but the wrong key means authentication fails first.
    assert {:error, :invalid} = open(token, @key_b)
  end

  # -------------------------------------------------------
  # Malformed input
  # -------------------------------------------------------

  test "empty string returns :malformed" do
    assert {:error, :malformed} = open("", @key)
  end

  test "random binary returns :malformed" do
    assert {:error, :malformed} = open("notavalidtoken!!!", @key)
  end

  test "truncated token returns :malformed" do
    token = seal("hello", @key, 60)
    truncated = binary_part(token, 0, div(byte_size(token), 4))
    assert {:error, :malformed} = open(truncated, @key)
  end

  test "valid base64 but too-short content returns :malformed" do
    # TODO
  end

  test "non-binary token returns :malformed" do
    assert {:error, :malformed} = open(12345, @key)
  end

  # -------------------------------------------------------
  # Key independence
  # -------------------------------------------------------

  test "tokens are not cross-openable across keys" do
    t1 = seal("msg", @key_a, 300)
    t2 = seal("msg", @key_b, 300)

    assert {:ok, "msg"} = open(t1, @key_a)
    assert {:ok, "msg"} = open(t2, @key_b)

    assert {:error, :invalid} = open(t1, @key_b)
    assert {:error, :invalid} = open(t2, @key_a)
  end

  # -------------------------------------------------------
  # Various payload types
  # -------------------------------------------------------

  test "supports atom payload" do
    token = seal(:hello, @key, 60)
    assert {:ok, :hello} = open(token, @key)
  end

  test "supports integer payload" do
    token = seal(12345, @key, 60)
    assert {:ok, 12345} = open(token, @key)
  end

  test "supports list payload" do
    token = seal([1, "two", :three], @key, 60)
    assert {:ok, [1, "two", :three]} = open(token, @key)
  end

  test "supports deeply nested map payload" do
    payload = %{a: %{b: %{c: "deep"}}}
    token = seal(payload, @key, 60)
    assert {:ok, ^payload} = open(token, @key)
  end

  test "authentic token whose plaintext is not a valid term returns :malformed" do
    now = Clock.now()
    nonce = :crypto.strong_rand_bytes(12)
    aad = <<now::64, now + 300::64>>

    {ciphertext, tag} =
      :crypto.crypto_one_time_aead(:aes_256_gcm, @key, nonce, "this-is-not-etf-data", aad, true)

    token =
      Base.url_encode64(
        <<nonce::binary-size(12), now::64, now + 300::64, tag::binary-size(16),
          ciphertext::binary>>,
        padding: false
      )

    assert {:error, :malformed} = open(token, @key)
  end
end
```
