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
defmodule CapabilityToken do
  @version 1
  @sig_size 32
  @max_caveat_size 65_535

  def mint(root_key, identifier) when is_binary(root_key) and is_binary(identifier) do
    signature = :crypto.mac(:hmac, :sha256, root_key, identifier)
    encode(identifier, [], signature)
  end

  def attenuate(token, caveat)
      when is_binary(token) and is_binary(caveat) and byte_size(caveat) in 1..@max_caveat_size do
    with {:ok, identifier, caveats, signature} <- decode(token) do
      new_signature = :crypto.mac(:hmac, :sha256, signature, caveat)
      {:ok, encode(identifier, caveats ++ [caveat], new_signature)}
    end
  end

  def attenuate(_token, _caveat), do: {:error, :malformed}

  def inspect_token(token) when is_binary(token) do
    with {:ok, identifier, caveats, _signature} <- decode(token) do
      {:ok, %{identifier: identifier, caveats: caveats}}
    end
  end

  def inspect_token(_token), do: {:error, :malformed}

  def authorize(token, root_key, context)
      when is_binary(token) and is_binary(root_key) and is_map(context) do
    with {:ok, identifier, caveats, signature} <- decode(token) do
      expected = chain(root_key, identifier, caveats)

      if secure_compare(expected, signature) do
        check_caveats(caveats, context)
      else
        {:error, :invalid_signature}
      end
    end
  end

  def authorize(_token, _root_key, _context), do: {:error, :malformed}

  # --- encoding -------------------------------------------------------------

  defp encode(identifier, caveats, signature) do
    body =
      for caveat <- caveats, into: <<>> do
        <<byte_size(caveat)::16, caveat::binary>>
      end

    binary =
      <<@version, byte_size(identifier)::16, identifier::binary, length(caveats)::16,
        body::binary, signature::binary-size(@sig_size)>>

    Base.url_encode64(binary, padding: false)
  end

  defp decode(token) do
    with {:ok, binary} <- Base.url_decode64(token, padding: false),
         <<@version, id_size::16, identifier::binary-size(id_size), count::16, rest::binary>> <-
           binary,
         {:ok, caveats, <<signature::binary-size(@sig_size)>>} <- take_caveats(count, rest, []) do
      {:ok, identifier, caveats, signature}
    else
      _other -> {:error, :malformed}
    end
  end

  defp take_caveats(0, rest, acc), do: {:ok, Enum.reverse(acc), rest}

  defp take_caveats(count, <<len::16, caveat::binary-size(len), rest::binary>>, acc)
       when count > 0 do
    take_caveats(count - 1, rest, [caveat | acc])
  end

  defp take_caveats(_count, _rest, _acc), do: :error

  # --- signatures -----------------------------------------------------------

  defp chain(root_key, identifier, caveats) do
    Enum.reduce(caveats, :crypto.mac(:hmac, :sha256, root_key, identifier), fn caveat, sig ->
      :crypto.mac(:hmac, :sha256, sig, caveat)
    end)
  end

  defp secure_compare(left, right) when byte_size(left) == byte_size(right) do
    left
    |> :binary.bin_to_list()
    |> Enum.zip(:binary.bin_to_list(right))
    |> Enum.reduce(0, fn {a, b}, acc -> Bitwise.bor(acc, Bitwise.bxor(a, b)) end)
    |> Kernel.==(0)
  end

  defp secure_compare(_left, _right), do: false

  # --- caveats --------------------------------------------------------------

  defp check_caveats([], _context), do: :ok

  defp check_caveats([caveat | rest], context) do
    if satisfied?(caveat, context) do
      check_caveats(rest, context)
    else
      {:error, {:caveat_failed, caveat}}
    end
  end

  defp satisfied?(caveat, context) do
    case :binary.split(caveat, " = ") do
      [key, value] -> satisfied?(key, value, context)
      _other -> false
    end
  end

  defp satisfied?("expires_at", value, context) do
    with {:ok, limit} <- parse_integer(value),
         now when is_integer(now) <- Map.get(context, :now) do
      now < limit
    else
      _other -> false
    end
  end

  defp satisfied?("action", value, context), do: Map.get(context, :action) === value

  defp satisfied?("resource_prefix", value, context) do
    case Map.get(context, :resource) do
      resource when is_binary(resource) -> String.starts_with?(resource, value)
      _other -> false
    end
  end

  defp satisfied?(_key, _value, _context), do: false

  defp parse_integer(value) do
    case Integer.parse(value) do
      {int, ""} -> {:ok, int}
      _other -> :error
    end
  end
end
```
