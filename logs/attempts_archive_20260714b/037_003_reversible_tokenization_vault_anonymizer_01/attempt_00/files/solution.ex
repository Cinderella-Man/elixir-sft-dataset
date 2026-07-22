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