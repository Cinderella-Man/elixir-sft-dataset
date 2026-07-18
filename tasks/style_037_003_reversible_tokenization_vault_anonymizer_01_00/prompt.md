# Bring this working module up to house style

I asked for the following:

Write me an Elixir module called `Anonymizer` that performs **reversible pseudonymization** (tokenization) of record fields, backed by a vault that can later restore the originals.

I need these functions in the public API:
- `Anonymizer.tokenize(records, fields)` where `records` is a list of maps and `fields` is a list of field-name atoms to pseudonymize. It returns `{tokenized_records, vault}`:
  - Each unique original value of a given field is replaced by a **stable opaque token string**. The token format is `"TOK_<FIELD>_<n>"` where `<FIELD>` is the uppercased field name and `<n>` is a per-field counter assigned in first-seen order (e.g. `"TOK_EMAIL_1"`).
  - Referential integrity: within a single `tokenize/2` call, the same original value for a field always produces the same token; different values produce different tokens. Distinct fields produce tokens in distinct namespaces even for equal values.
  - Fields not listed, and listed fields absent from a given record, are left untouched.
  - `vault` is an opaque term that records the mapping needed to reverse the transformation.
- `Anonymizer.detokenize(records, vault)` returns the list of records with every value that is a known token (per the vault) replaced by its original value. Values that are not known tokens are left exactly as-is.

The round trip must be lossless: `detokenize(tokenize(records, fields) |> elem(0), vault)` must equal the original `records`.

Use only the Elixir/OTP standard library — no external dependencies. Give me the complete module in a single file.

Here is my implementation. It compiles and passes every test — the behavior
is correct — but it was rejected by the style review:

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

  @spec tokenize([map()], [atom()]) :: {[map()], vault()}
  def tokenize(records, fields) when is_list(records) and is_list(fields) do
    {reversed, vault} =
      Enum.reduce(records, {[], new_vault()}, fn record, {acc, vault} ->
        {record2, vault2} =
          Enum.reduce(fields, {record, vault}, fn field, {rec, v} ->
            case Map.fetch(rec, field) do
              {:ok, value} ->
                {token, v2} = get_or_create_token(v, field, value)
                {Map.put(rec, field, token), v2}

              :error ->
                {rec, v}
            end
          end)

        {[record2 | acc], vault2}
      end)

    {Enum.reverse(reversed), vault}
  end

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

The style review said:

```
The solution is green but does not meet the house style: no @doc on any public function. Fix solution.ex so it has a `@moduledoc`, an `@spec` and `@doc` on public functions, no `TODO` markers, and compiles with ZERO warnings. Keep the behavior identical and do not weaken test_harness.exs.
```

Fix every finding in the review WITHOUT changing any behavior: the module
must keep passing exactly the tests it passes now. Give me the complete
corrected module in a single file.
<!-- minted from logs/attempts/037_003_reversible_tokenization_vault_anonymizer_01/attempt_0 -->
