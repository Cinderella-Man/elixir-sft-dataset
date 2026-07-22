defmodule DataQualityScorer do
  @moduledoc """
  Scores the quality of a dataset against a set of declarative quality rules.

  A dataset is a list of records (maps keyed by field-name atoms). Rules are a
  map of `%{field_name => [rule, ...]}` where each field maps to a non-empty
  list of rules to enforce on that field.

  Supported rule types:

    * `:not_null` — the field key is present and its value is not `nil`.
    * `:unique` — the value appears exactly once across all records.
    * `{:format, regex}` — the value is a binary string matching `regex`.
    * `{:range, min, max}` — the value is a number within `[min, max]`.
    * `{:referential, set}` — the value is a member of the given `MapSet`.

  `score/2` returns overall, per-record and per-field percentage scores.
  """

  @typedoc "A single dataset record."
  @type record :: %{optional(atom()) => any()}

  @typedoc "A single quality rule."
  @type rule ::
          :not_null
          | :unique
          | {:format, Regex.t()}
          | {:range, number(), number()}
          | {:referential, MapSet.t()}

  @typedoc "Rules keyed by field name."
  @type rules :: %{optional(atom()) => [rule(), ...]}

  @typedoc "Per-record result."
  @type record_result :: %{
          score: float(),
          passed: non_neg_integer(),
          total: non_neg_integer()
        }

  @typedoc "The full scoring result."
  @type result :: %{
          overall: float(),
          records: [record_result()],
          fields: %{optional(atom()) => float()}
        }

  @doc """
  Scores `records` against `rules`.

  Returns a map with `:overall`, `:records` and `:fields` keys. Percentages are
  plain floats and are not rounded. Empty datasets and rule-free scorings score
  `100.0` (vacuously true).

  ## Examples

      iex> rules = %{name: [:not_null]}
      iex> DataQualityScorer.score([%{name: "a"}, %{name: nil}], rules)
      %{
        overall: 50.0,
        records: [
          %{score: 100.0, passed: 1, total: 1},
          %{score: +0.0, passed: 0, total: 1}
        ],
        fields: %{name: 50.0}
      }
  """
  @spec score([record()], rules()) :: result()
  def score(records, rules) when is_list(records) and is_map(rules) do
    fields = Map.keys(rules)
    total_rules = rules |> Map.values() |> Enum.map(&length/1) |> Enum.sum()

    tallies = build_tallies(records, fields)

    record_results = Enum.map(records, &score_record(&1, rules, tallies, total_rules))
    fields_result = score_fields(records, rules, tallies)
    overall = score_overall(record_results, length(records), total_rules)

    %{overall: overall, records: record_results, fields: fields_result}
  end

  # Precompute value frequencies per field, for `:unique` rules.
  @spec build_tallies([record()], [atom()]) :: %{optional(atom()) => %{any() => pos_integer()}}
  defp build_tallies(records, fields) do
    Map.new(fields, fn field ->
      counts =
        Enum.reduce(records, %{}, fn record, acc ->
          value = Map.get(record, field)
          Map.update(acc, value, 1, &(&1 + 1))
        end)

      {field, counts}
    end)
  end

  @spec score_record(record(), rules(), map(), non_neg_integer()) :: record_result()
  defp score_record(record, rules, tallies, total_rules) do
    passed =
      Enum.reduce(rules, 0, fn {field, field_rules}, acc ->
        acc + Enum.count(field_rules, &rule_passes?(&1, record, field, tallies))
      end)

    %{score: percentage(passed, total_rules), passed: passed, total: total_rules}
  end

  @spec score_fields([record()], rules(), map()) :: %{optional(atom()) => float()}
  defp score_fields(records, rules, tallies) do
    count = length(records)

    Map.new(rules, fn {field, field_rules} ->
      passing =
        Enum.count(records, fn record ->
          Enum.all?(field_rules, &rule_passes?(&1, record, field, tallies))
        end)

      {field, field_percentage(passing, count)}
    end)
  end

  @spec score_overall([record_result()], non_neg_integer(), non_neg_integer()) :: float()
  defp score_overall(_record_results, 0, _total_rules), do: 100.0
  defp score_overall(_record_results, _count, 0), do: 100.0

  defp score_overall(record_results, count, total_rules) do
    total_passed = record_results |> Enum.map(& &1.passed) |> Enum.sum()
    percentage(total_passed, count * total_rules)
  end

  @spec rule_passes?(rule(), record(), atom(), map()) :: boolean()
  defp rule_passes?(:not_null, record, field, _tallies) do
    Map.has_key?(record, field) and Map.get(record, field) != nil
  end

  defp rule_passes?(:unique, record, field, tallies) do
    value = Map.get(record, field)
    counts = Map.fetch!(tallies, field)
    Map.get(counts, value) == 1
  end

  defp rule_passes?({:format, regex}, record, field, _tallies) do
    value = Map.get(record, field)
    is_binary(value) and Regex.match?(regex, value)
  end

  defp rule_passes?({:range, lo, hi}, record, field, _tallies) do
    value = Map.get(record, field)
    is_number(value) and lo <= value and value <= hi
  end

  defp rule_passes?({:referential, set}, record, field, _tallies) do
    MapSet.member?(set, Map.get(record, field))
  end

  # Score for a single record's rule tally; empty rule set scores 100.0.
  @spec percentage(non_neg_integer(), non_neg_integer()) :: float()
  defp percentage(_passed, 0), do: 100.0
  defp percentage(passed, total), do: passed / total * 100

  # Field score; an empty dataset scores 100.0 vacuously.
  @spec field_percentage(non_neg_integer(), non_neg_integer()) :: float()
  defp field_percentage(_passing, 0), do: 100.0
  defp field_percentage(passing, count), do: passing / count * 100
end