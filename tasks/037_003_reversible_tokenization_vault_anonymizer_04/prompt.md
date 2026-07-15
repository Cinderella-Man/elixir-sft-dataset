Implement the public `detokenize/2` function. It takes `records` (a list of maps)
and `vault` (the opaque term returned by `tokenize/2`) and returns the list of
records with every known token restored to its original value. Read the reverse
mapping from the vault via `Map.get(vault, :reverse, %{})`. Then map over each
record and rebuild it with `Map.new/2`, transforming every `{key, value}` pair so
that if `value` is a known token it is replaced by its original (via
`Map.get(reverse, value, value)`), and any value that is not a known token is left
exactly as-is. This is the inverse of `tokenize/2`, making the round trip lossless.

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
    # TODO
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