defmodule Anonymizer do
  @moduledoc """
  Reversible pseudonymization (tokenization) of record fields.

  `tokenize/2` replaces each selected field value with a stable, opaque token of
  the form `"TOK_<FIELD>_<n>"`, where `<FIELD>` is the uppercased field name and
  `<n>` is a per-field, first-seen counter. It returns the transformed records
  together with an opaque `vault` term.

  `detokenize/2` uses that vault to restore original values, replacing any value
  that is a known token and leaving everything else untouched. The round trip is
  lossless: detokenizing the tokenized records with the returned vault yields the
  original records.
  """

  @typedoc "A single record: a map keyed by field-name atoms."
  @type record :: %{optional(atom()) => term()}

  @typedoc "Opaque reversal mapping from token string to original value."
  @opaque vault :: %{optional(String.t()) => term()}

  @doc """
  Pseudonymize `fields` across `records`.

  Each unique original value of a listed field is replaced by a stable token
  string `"TOK_<FIELD>_<n>"`, with `<n>` assigned in first-seen order per field.
  Equal values within one field share a token; distinct fields use distinct
  token namespaces even for equal values. Fields not listed, and listed fields
  absent from a given record, are left untouched. Duplicate entries in `fields`
  are ignored (never applied as a second pass).

  Returns `{tokenized_records, vault}` where `vault` is an opaque term suitable
  for `detokenize/2`.
  """
  @spec tokenize([record()], [atom()]) :: {[record()], vault()}
  def tokenize(records, fields) when is_list(records) and is_list(fields) do
    unique_fields = Enum.uniq(fields)

    forward =
      Enum.reduce(unique_fields, %{}, fn field, acc ->
        Map.put(acc, field, build_field_map(records, field))
      end)

    vault = build_vault(forward)
    tokenized = Enum.map(records, &tokenize_record(&1, unique_fields, forward))
    {tokenized, vault}
  end

  @doc """
  Restore original values in `records` using `vault`.

  Every value that is a known token (per `vault`) is replaced by its original
  value; all other values are left exactly as-is.
  """
  @spec detokenize([record()], vault()) :: [record()]
  def detokenize(records, vault) when is_list(records) and is_map(vault) do
    Enum.map(records, fn record ->
      Map.new(record, fn {key, value} -> {key, detokenize_value(value, vault)} end)
    end)
  end

  @spec build_field_map([record()], atom()) :: %{optional(term()) => String.t()}
  defp build_field_map(records, field) do
    prefix = "TOK_" <> String.upcase(Atom.to_string(field)) <> "_"

    {map, _counter} =
      Enum.reduce(records, {%{}, 0}, fn record, {map, counter} = state ->
        case Map.fetch(record, field) do
          {:ok, value} ->
            if Map.has_key?(map, value) do
              state
            else
              next = counter + 1
              {Map.put(map, value, prefix <> Integer.to_string(next)), next}
            end

          :error ->
            state
        end
      end)

    map
  end

  @spec tokenize_record(record(), [atom()], map()) :: record()
  defp tokenize_record(record, fields, forward) do
    Enum.reduce(fields, record, fn field, acc ->
      case Map.fetch(acc, field) do
        {:ok, value} ->
          token = forward |> Map.fetch!(field) |> Map.fetch!(value)
          Map.put(acc, field, token)

        :error ->
          acc
      end
    end)
  end

  @spec build_vault(map()) :: vault()
  defp build_vault(forward) do
    Enum.reduce(forward, %{}, fn {_field, value_map}, acc ->
      Enum.reduce(value_map, acc, fn {value, token}, inner ->
        Map.put(inner, token, value)
      end)
    end)
  end

  @spec detokenize_value(term(), vault()) :: term()
  defp detokenize_value(value, vault) when is_binary(value) do
    case Map.fetch(vault, value) do
      {:ok, original} -> original
      :error -> value
    end
  end

  defp detokenize_value(value, _vault), do: value
end