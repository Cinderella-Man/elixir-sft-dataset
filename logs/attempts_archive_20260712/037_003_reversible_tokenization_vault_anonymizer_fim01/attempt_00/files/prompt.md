Implement the private `get_or_create_token/3` function.

`get_or_create_token(vault, field, value)` looks up (and, when necessary,
mints) the stable token for a single `{field, value}` pair. It builds its
lookup key as the two-element tuple `{field, value}` so that distinct fields
occupy distinct namespaces even when their values are equal.

- If that key already exists in `vault.forward`, the value has been seen before:
  return `{existing_token, vault}` unchanged — this guarantees referential
  integrity (the same original value for a field always yields the same token).
- Otherwise this is a first sighting. Read the current per-field counter from
  `vault.counters` (defaulting to `0` when the field has none yet) and increment
  it by one to obtain `n`. Build the token string
  `"TOK_<FIELD>_<n>"`, where `<FIELD>` is the uppercased field name (turn the
  field atom into a string and upcase it) and `<n>` is the decimal counter.
  Then return `{token, updated_vault}`, where `updated_vault` has:
  - the new mapping `{field, value} => token` added to `forward`,
  - the inverse mapping `token => value` added to `reverse`, and
  - `field => n` written into `counters`.

The counter is per-field and assigned in first-seen order, so the first unique
`:email` value becomes `"TOK_EMAIL_1"`, the second `"TOK_EMAIL_2"`, and so on.

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
    # TODO
  end
end
```