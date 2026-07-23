# Fix the bug

The module below was written for the task that follows, but ONE behavior bug
slipped in. The test suite (not shown) fails with the report at the bottom.
Find the bug and fix it — change as little as possible; do not restructure
working code. Reply with the complete corrected module.

## The task the module implements

# Reversible Tokenization Vault — `Anonymizer` Specification

## Overview

This document specifies an Elixir module named `Anonymizer` that performs **reversible pseudonymization** (tokenization) of record fields, backed by a vault that can later restore the originals.

The implementation must use only the Elixir/OTP standard library — no external dependencies. The complete module is to be delivered in a single file.

## API

The module exposes the following functions in its public API.

### `Anonymizer.tokenize(records, fields)`

Here `records` is a list of maps and `fields` is a list of field-name atoms to pseudonymize. It returns `{tokenized_records, vault}`, subject to the following behavior:

- Each unique original value of a given field is replaced by a **stable opaque token string**. The token format is `"TOK_<FIELD>_<n>"` where `<FIELD>` is the uppercased field name and `<n>` is a per-field counter assigned in first-seen order (e.g. `"TOK_EMAIL_1"`).
- Referential integrity: within a single `tokenize/2` call, the same original value for a field always produces the same token; different values produce different tokens. Distinct fields produce tokens in distinct namespaces even for equal values.
- `vault` is an opaque term that records the mapping needed to reverse the transformation.

### `Anonymizer.detokenize(records, vault)`

This function returns the list of records with every value that is a known token (per the vault) replaced by its original value. Values that are not known tokens are left exactly as-is.

## Edge cases

- Fields not listed, and listed fields absent from a given record, are left untouched.
- Listing the same field more than once behaves exactly like listing it once: duplicate entries in `fields` are ignored, never applied as a second tokenization pass.
- The round trip must be lossless: `detokenize(tokenize(records, fields) |> elem(0), vault)` must equal the original `records`.

## The buggy module

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
    # A duplicate field atom must behave like a single mention: a second pass
    # over an already-tokenized field would tokenize the token itself, and the
    # round trip through detokenize/2 would no longer be lossless.
    fields = Enum.uniq(fields)

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
      {:error, token} ->
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

## Failing test report

```
4 of 12 test(s) failed:

  * test tokenize referential integrity: same value maps to same token
      no case clause matching:
      
          {:ok, "TOK_EMAIL_1"}
      

  * test tokenize counter advances only on first sight of a value, not on repeats
      no case clause matching:
      
          {:ok, "TOK_EMAIL_1"}
      

  * test tokenize each field counts from 1 independently in its own namespace
      no case clause matching:
      
          {:ok, "TOK_SSN_1"}
      

  * test detokenize round trip restores original records exactly
      no case clause matching:
      
          {:ok, "TOK_EMAIL_1"}
```
