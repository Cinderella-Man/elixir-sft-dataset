defmodule Anonymizer do
  @moduledoc """
  Reversible pseudonymization (tokenization) of record fields with a vault.

  `tokenize/2` replaces each unique original value of a listed field with a
  stable opaque token (`"TOK_<FIELD>_<n>"`, `n` assigned in first-seen order)
  and returns `{tokenized_records, vault}`. `detokenize/2` uses the vault to
  restore originals, leaving any non-token value untouched. The round trip is
  lossless. Only OTP/stdlib modules are used.

  Because a token is recognized purely by its string value, a token must never
  be equal to a string that already lives in the input records: such a literal
  would be indistinguishable from a real token and would be rewritten by
  `detokenize/2`. `tokenize/2` therefore skips any counter position whose token
  collides with a pre-existing value, keeping the round trip lossless.
  """

  @type vault :: %{forward: map(), reverse: map(), counters: map(), taboo: MapSet.t()}

  @doc """
  Pseudonymizes `fields` across `records`.

  Each unique original value of a listed field is replaced by a stable opaque
  token of the form `"TOK_<FIELD>_<n>"`, where `<FIELD>` is the uppercased
  field name and `<n>` is a per-field, first-seen counter. Distinct fields use
  distinct namespaces even for equal values. Fields not listed, and listed
  fields absent from a record, are left untouched. Counter positions whose
  token would collide with a string already present in `records` are skipped.

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
      Enum.reduce(records, {[], new_vault(records)}, fn record, {acc, vault} ->
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

  defp new_vault(records) do
    %{forward: %{}, reverse: %{}, counters: %{}, taboo: collect_literals(records)}
  end

  # Every binary already present in the input is off-limits as a token: it
  # would be ambiguous with a genuine token at detokenize/2 time.
  defp collect_literals(records) do
    Enum.reduce(records, MapSet.new(), fn record, acc ->
      Enum.reduce(record, acc, fn
        {_k, v}, acc when is_binary(v) -> MapSet.put(acc, v)
        {_k, _v}, acc -> acc
      end)
    end)
  end

  defp get_or_create_token(vault, field, value) do
    key = {field, value}

    case Map.fetch(vault.forward, key) do
      {:ok, token} ->
        {token, vault}

      :error ->
        {n, token} = next_free_token(vault, field)

        vault = %{
          vault
          | forward: Map.put(vault.forward, key, token),
            reverse: Map.put(vault.reverse, token, value),
            counters: Map.put(vault.counters, field, n)
        }

        {token, vault}
    end
  end

  defp next_free_token(vault, field) do
    prefix = "TOK_" <> String.upcase(Atom.to_string(field)) <> "_"
    n = Map.get(vault.counters, field, 0) + 1
    advance_past_collisions(vault.taboo, prefix, n)
  end

  defp advance_past_collisions(taboo, prefix, n) do
    token = prefix <> Integer.to_string(n)

    if MapSet.member?(taboo, token) do
      advance_past_collisions(taboo, prefix, n + 1)
    else
      {n, token}
    end
  end
end
