# Document this module

Below is a complete, working, tested Elixir module. Its behavior is correct
and must not change — but every piece of documentation has been stripped.

Add the missing documentation and typespecs:

- a `@moduledoc` that explains what the module does and how it is used,
- a `@doc` for every public function,
- a `@spec` for every public function (add `@type`s where they make the
  specs clearer).

Do not change any behavior: every function clause, guard, and expression
must keep working exactly as it does now. Do not rename anything, do not
"improve" the code, and do not add or remove functions. Give me the
complete documented module in a single file.

## The module

```elixir
defmodule SealedToken do
  @cipher :aes_256_gcm
  @nonce_size 12
  @tag_size 16

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

  def open(token, key, opts \\ []) do
    with true <- is_binary(token),
         {:ok, binary} <- decode(token),
         {:ok, nonce, issued_at, expires_at, tag, ciphertext} <- parse(binary) do
      decrypt_and_validate(key, nonce, issued_at, expires_at, tag, ciphertext, opts)
    else
      _ -> {:error, :malformed}
    end
  end

  defp decode(token), do: Base.url_decode64(token, padding: false)

  defp parse(
         <<nonce::binary-size(@nonce_size), issued_at::64, expires_at::64,
           tag::binary-size(@tag_size), ciphertext::binary>>
       ) do
    {:ok, nonce, issued_at, expires_at, tag, ciphertext}
  end

  defp parse(_binary), do: :error

  defp decrypt_and_validate(key, nonce, issued_at, expires_at, tag, ciphertext, opts) do
    aad = <<issued_at::64, expires_at::64>>

    case :crypto.crypto_one_time_aead(@cipher, key, nonce, ciphertext, aad, tag, false) do
      :error ->
        {:error, :invalid}

      plaintext when is_binary(plaintext) ->
        validate_and_deserialize(plaintext, expires_at, opts)
    end
  end

  defp validate_and_deserialize(plaintext, expires_at, opts) do
    if now(opts) < expires_at do
      deserialize(plaintext)
    else
      {:error, :expired}
    end
  end

  defp deserialize(plaintext) do
    {:ok, :erlang.binary_to_term(plaintext, [:safe])}
  rescue
    ArgumentError -> {:error, :malformed}
  end

  defp now(opts) do
    case Keyword.get(opts, :clock) do
      fun when is_function(fun, 0) -> fun.()
      _ -> System.os_time(:second)
    end
  end
end
```
