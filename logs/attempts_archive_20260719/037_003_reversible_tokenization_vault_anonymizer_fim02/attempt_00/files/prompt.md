Implement the public `tokenize/2` function. It takes `records` (a list of maps)
and `fields` (a list of field-name atoms) and returns `{tokenized_records, vault}`.
It should fold over `records`, threading a fresh vault (from `new_vault/0`) through
the whole traversal. For each record, fold over `fields`: when the record has the
field (`Map.fetch/2` returns `{:ok, value}`), obtain a stable token for that
`{field, value}` pair via `get_or_create_token/3` and `Map.put/3` the token back
into the record, threading the updated vault forward; when the field is absent
(`:error`), leave the record and vault unchanged. Accumulate the transformed
records in reverse order and `Enum.reverse/1` them at the end, returning the list
together with the final vault. The guard should require `records` and `fields` to
both be lists.

```elixir
defmodule Anonymizer do
  @moduledoc """
  Reversible pseudonymization (tokenization) of record fields with a vault.

  `tokenize/2` replaces each unique original value of a listed field with a
  stable opaque token (`"TOK_<FIELD>_<n>"`, `n` assigned in first-seen order)
  and returns `{tokenized_records, vault}`. `detokenize/2` uses the vault to
  restore originals, leaving any non-token value untouched. The round trip is
  lossless. Only OTP/stdlib modules are used.
  """

  @type vault :: %{forward: map(), reverse: map(), counters: map()}

  @doc """
  Pseudonymizes `fields` across `records`.

  Each unique original value of a listed field is replaced by a stable opaque
  token of the form `"TOK_<FIELD>_<n>"`, where `<FIELD>` is the uppercased
  field name and `<n>` is a per-field, first-seen counter. Distinct fields use
  distinct namespaces even for equal values. Fields not listed, and listed
  fields absent from a record, are left untouched.

  Returns `{tokenized_records, vault}`, where `vault` is an opaque term that
  records the mapping needed to reverse the transformation.
  """
  @spec tokenize([map()], [atom()]) :: {[map()], vault()}
  def tokenize(records, fields) when is_list(records) and is_list(fields) do
    # TODO
  end

  @doc """
  Restores original values in `records` using `vault`.

  Every value that is a known token (per the vault) is replaced by its original
  value; values that are not known tokens are left exactly as-is. This is the
  inverse of `tokenize/2`.
  """
  @spec detokenize([map()], vault()) :: [map()]
  def detokenize(records, vault) when is_list(records) and is_map(vault) do
    reverse = Map.get(vault, :reverse, %{})

    Enum.map(records, fn record ->
      Map.new(record, fn {k, v} -> {k, Map.get(reverse, v, v)} end)
    end)
  end

  # --- Internal ---------------------------------------------------------------

  defp new_vault, do: %{forward: %{}, reverse: %{}, counters: %{}}

  defp get_or_create_token(vault, field, value) do
    key = {field, value}

    case Map.fetch(vault.forward, key) do
      {:ok, token} ->
        {token, vault}

      :error ->
        n = Map.get(vault.counters, field, 0) + 1
        token = "TOK_" <> String.upcase(Atom.to_string(field)) <> "_" <> Integer.to_string(n)

        vault = %{
          forward: Map.put(vault.forward, key, token),
          reverse: Map.put(vault.reverse, token, value),
          counters: Map.put(vault.counters, field, n)
        }

        {token, vault}
    end
  end
end
```