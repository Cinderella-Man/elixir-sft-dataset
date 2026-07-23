# Implement the missing function

The specification below is followed by its complete, tested solution —
minus `validate_compare_fields`, whose clause bodies are all `# TODO`. Supply that one
function; the rest of the module is fixed and must stay exactly as shown.

## The task

# Design Brief: `TolerantReconciler`

## Problem

Two lists of records must be reconciled against each other, but strict equality is too blunt: a 0.005 rounding difference on a money column, or a stray capital letter in a name, should not count as a mismatch. The needed component is an Elixir module called `TolerantReconciler` that reconciles two lists of records using **per-field comparison rules** instead of strict equality. The design is split into a validated-configuration stage and an execution stage.

## Constraints

- Pure functions — no processes, no side effects, no external dependencies. Elixir standard library only.
- Deliver the complete module in a single file.

## Required Interface

1. **`TolerantReconciler.compile(opts)`** — validates a keyword list and returns `{:ok, config}` or `{:error, reason}`.

   Options:
   - `:key_fields` (required) — a non-empty list of atoms forming the composite key.
   - `:compare_fields` (optional) — a list of atoms to compare on matched pairs. If omitted or `nil`, compare every field present in either record of the pair, minus the key fields.
   - `:rules` (optional) — a keyword list of `field => rule`. Any compared field with no entry here uses the `:exact` rule. Defaults to `[]`.

   Rules:
   - `:exact` — the values differ unless `left == right`.
   - `{:numeric, tolerance}` — `tolerance` must be a number `>= 0`. If **both** values are numbers, they are considered equal when `abs(left - right) <= tolerance`. If either value is not a number, fall back to `==`.
   - `:case_insensitive` — if **both** values are binaries, they are considered equal when their trimmed, downcased forms are equal (`String.trim/1` then `String.downcase/1`). If either value is not a binary, fall back to `==`.
   - `:ignore` — the field is never compared and can never appear in a differences map, even if it is listed in `:compare_fields`.

   Errors — return exactly these error tuples (first failure wins is not required — any one of the applicable errors is acceptable when several apply):
   - `{:error, :missing_key_fields}` — `:key_fields` is absent.
   - `{:error, :invalid_key_fields}` — `:key_fields` is present but is not a non-empty list of atoms.
   - `{:error, :invalid_compare_fields}` — `:compare_fields` is present, not `nil`, and is not a list of atoms.
   - `{:error, :invalid_rules}` — `:rules` is not a keyword list (a list of `{atom, term}` pairs).
   - `{:error, {:invalid_rule, field}}` — the rule given for `field` is not one of the four rules above (including a `{:numeric, tolerance}` whose tolerance is not a number `>= 0`).

   On success the return is `{:ok, config}`. The shape of `config` is up to you — treat it as opaque; it is only ever passed back into `run/3`.

2. **`TolerantReconciler.run(config, left, right)`** — runs the reconciliation, where `left` and `right` are lists of maps. Returns a report map.

   Matching: records are matched across the two lists by **exact** equality on all key fields (comparison rules apply to compared fields only, never to key fields). A key field missing from a record is treated as `nil`. If a key repeats within one list, the last record with that key wins.

   The report is a map with three keys:
   - `:matched` — a list of `%{left: record, right: record, differences: diff_map}` for keys present on both sides. `diff_map` is `%{field => %{left: left_value, right: right_value, rule: rule}}` for every compared field whose values differ **under its rule**, where `rule` is the rule that was applied (`:exact` when the field had no entry in `:rules`). `diff_map` is `%{}` when the pair agrees under all rules. A compared field missing from a record is treated as `nil`. The `:left` and `:right` records are the full originals.
   - `:only_in_left` — records whose key appears only in `left`.
   - `:only_in_right` — records whose key appears only in `right`.

   Order of results does not matter.

3. **`TolerantReconciler.field_summary(report)`** — takes a report from `run/3` and returns a map of `%{field => number_of_matched_pairs_where_it_differed}`. Given a report from `run/3`, return a map from field name to the number of entries in `:matched` whose `differences` map contains that field. Fields that never differed are **omitted** from the map (so an all-clean report gives `%{}`).

## Acceptance Criteria

- `compile/1` validates the keyword list, returns `{:ok, config}` on success and the exact error tuples above on failure, applies the rule semantics described (`:exact`, `{:numeric, tolerance}` with `tolerance` a number `>= 0`, `:case_insensitive`, `:ignore`), and defaults `:rules` to `[]` with `:exact` for any compared field lacking an entry.
- `run/3` matches by exact equality on all key fields (missing key field treated as `nil`, last record wins on repeated keys within a list), produces `:matched`, `:only_in_left`, and `:only_in_right`, and builds each `diff_map` correctly (missing compared field treated as `nil`, `:ignore` fields never present, `%{}` when a pair agrees).
- `field_summary/1` returns a map from field to the count of `:matched` entries whose `differences` contains that field, omitting fields that never differed (`%{}` for an all-clean report).
- The module is pure — no processes, no side effects, no external dependencies, Elixir standard library only — and delivered complete in a single file.

## The module with `validate_compare_fields` missing

```elixir
defmodule TolerantReconciler do
  @moduledoc """
  Reconciles two lists of record maps using per-field comparison rules rather than
  strict equality.

  The module is split into two stages:

    * `compile/1` validates a keyword list of options and produces an opaque
      configuration value.
    * `run/3` executes a reconciliation of two lists of maps against that
      configuration and returns a report.

  Records are paired across the two lists by exact equality on the composite key
  built from `:key_fields`. Comparison rules never apply to key fields. Compared
  fields are checked with the rule configured for them (defaulting to `:exact`),
  so a small numeric drift or a difference in letter case need not count as a
  mismatch.

  Supported rules:

    * `:exact` — values differ unless `left == right`.
    * `{:numeric, tolerance}` — when both values are numbers, they are equal when
      `abs(left - right) <= tolerance`; otherwise falls back to `==`.
    * `:case_insensitive` — when both values are binaries, they are equal when
      their trimmed and downcased forms are equal; otherwise falls back to `==`.
    * `:ignore` — the field is never compared.

  All functions are pure: no processes, no side effects, no external dependencies.
  """

  @type field :: atom()
  @type rule :: :exact | :ignore | :case_insensitive | {:numeric, number()}
  @type record_map :: map()
  @type difference :: %{left: term(), right: term(), rule: rule()}
  @type differences :: %{optional(field()) => difference()}
  @type matched_pair :: %{
          left: record_map(),
          right: record_map(),
          differences: differences()
        }
  @type report :: %{
          matched: [matched_pair()],
          only_in_left: [record_map()],
          only_in_right: [record_map()]
        }

  @opaque config :: %__MODULE__{
            key_fields: [field()],
            compare_fields: [field()] | nil,
            rules: %{optional(field()) => rule()}
          }

  @enforce_keys [:key_fields, :compare_fields, :rules]
  defstruct [:key_fields, :compare_fields, :rules]

  @doc """
  Validates reconciliation options and returns an opaque configuration.

  ## Options

    * `:key_fields` (required) — a non-empty list of atoms forming the composite key.
    * `:compare_fields` (optional) — a list of atoms to compare on matched pairs. When
      omitted or `nil`, every field present in either record of a pair is compared,
      minus the key fields.
    * `:rules` (optional) — a keyword list of `field => rule`. Compared fields without
      an entry use the `:exact` rule. Defaults to `[]`.

  Returns `{:ok, config}` or one of `{:error, :missing_key_fields}`,
  `{:error, :invalid_key_fields}`, `{:error, :invalid_compare_fields}`,
  `{:error, :invalid_rules}` or `{:error, {:invalid_rule, field}}`.

  ## Examples

      iex> {:ok, config} = TolerantReconciler.compile(key_fields: [:id])
      iex> match?(%TolerantReconciler{}, config)
      true

      iex> TolerantReconciler.compile([])
      {:error, :missing_key_fields}
  """
  @spec compile(keyword()) ::
          {:ok, config()}
          | {:error,
             :missing_key_fields
             | :invalid_key_fields
             | :invalid_compare_fields
             | :invalid_rules
             | {:invalid_rule, field()}}
  def compile(opts) when is_list(opts) do
    with {:ok, key_fields} <- validate_key_fields(opts),
         {:ok, compare_fields} <- validate_compare_fields(opts),
         {:ok, rules} <- validate_rules(opts) do
      {:ok,
       %__MODULE__{
         key_fields: key_fields,
         compare_fields: compare_fields,
         rules: rules
       }}
    end
  end

  def compile(_opts), do: {:error, :missing_key_fields}

  @doc """
  Reconciles `left` and `right` (lists of maps) using the compiled `config`.

  Records are paired by exact equality on all key fields; a key field missing from a
  record is treated as `nil`. When a key repeats within one list, the last record with
  that key wins.

  Returns a report map with:

    * `:matched` — `%{left: record, right: record, differences: diff_map}` for every key
      present on both sides, where `diff_map` maps each differing compared field to
      `%{left: value, right: value, rule: rule}`.
    * `:only_in_left` — records whose key appears only in `left`.
    * `:only_in_right` — records whose key appears only in `right`.

  ## Examples

      iex> {:ok, config} =
      ...>   TolerantReconciler.compile(key_fields: [:id], rules: [amount: {:numeric, 0.01}])
      iex> report =
      ...>   TolerantReconciler.run(config, [%{id: 1, amount: 10.0}], [%{id: 1, amount: 10.005}])
      iex> Enum.map(report.matched, & &1.differences)
      [%{}]
  """
  @spec run(config(), [record_map()], [record_map()]) :: report()
  def run(%__MODULE__{} = config, left, right) when is_list(left) and is_list(right) do
    left_index = index_by_key(left, config.key_fields)
    right_index = index_by_key(right, config.key_fields)

    left_keys = left_index |> Map.keys() |> MapSet.new()
    right_keys = right_index |> Map.keys() |> MapSet.new()

    matched =
      left_keys
      |> MapSet.intersection(right_keys)
      |> Enum.map(fn key ->
        left_record = Map.fetch!(left_index, key)
        right_record = Map.fetch!(right_index, key)

        %{
          left: left_record,
          right: right_record,
          differences: diff_records(config, left_record, right_record)
        }
      end)

    %{
      matched: matched,
      only_in_left: records_for(left_index, MapSet.difference(left_keys, right_keys)),
      only_in_right: records_for(right_index, MapSet.difference(right_keys, left_keys))
    }
  end

  @doc """
  Summarises how often each field differed across the matched pairs of a report.

  Returns a map of `%{field => number_of_matched_pairs_where_it_differed}`. Fields that
  never differed are omitted, so an all-clean report yields `%{}`.

  ## Examples

      iex> {:ok, config} = TolerantReconciler.compile(key_fields: [:id])
      iex> report = TolerantReconciler.run(config, [%{id: 1, name: "a"}], [%{id: 1, name: "b"}])
      iex> TolerantReconciler.field_summary(report)
      %{name: 1}
  """
  @spec field_summary(report()) :: %{optional(field()) => pos_integer()}
  def field_summary(%{matched: matched}) when is_list(matched) do
    Enum.reduce(matched, %{}, fn %{differences: differences}, acc ->
      Enum.reduce(Map.keys(differences), acc, fn field, inner ->
        Map.update(inner, field, 1, &(&1 + 1))
      end)
    end)
  end

  # -- validation ----------------------------------------------------------------

  defp validate_key_fields(opts) do
    case Keyword.fetch(opts, :key_fields) do
      :error -> {:error, :missing_key_fields}
      {:ok, [_ | _] = fields} -> if atoms?(fields), do: {:ok, fields}, else: key_error()
      {:ok, _other} -> key_error()
    end
  end

  defp key_error, do: {:error, :invalid_key_fields}

  defp validate_compare_fields(opts) do
    # TODO
  end

  defp compare_fields_or_error(fields) do
    if atoms?(fields), do: {:ok, fields}, else: {:error, :invalid_compare_fields}
  end

  defp validate_rules(opts) do
    case Keyword.fetch(opts, :rules) do
      :error -> {:ok, %{}}
      {:ok, rules} when is_list(rules) -> build_rules(rules)
      {:ok, _other} -> {:error, :invalid_rules}
    end
  end

  defp build_rules(rules) do
    if Keyword.keyword?(rules) do
      Enum.reduce_while(rules, {:ok, %{}}, fn {field, rule}, {:ok, acc} ->
        if valid_rule?(rule) do
          {:cont, {:ok, Map.put(acc, field, rule)}}
        else
          {:halt, {:error, {:invalid_rule, field}}}
        end
      end)
    else
      {:error, :invalid_rules}
    end
  end

  defp valid_rule?(:exact), do: true
  defp valid_rule?(:ignore), do: true
  defp valid_rule?(:case_insensitive), do: true
  defp valid_rule?({:numeric, tolerance}) when is_number(tolerance), do: tolerance >= 0
  defp valid_rule?(_rule), do: false

  defp atoms?(list), do: Enum.all?(list, &is_atom/1)

  # -- execution -----------------------------------------------------------------

  defp index_by_key(records, key_fields) do
    Enum.reduce(records, %{}, fn record, acc ->
      Map.put(acc, key_of(record, key_fields), record)
    end)
  end

  defp key_of(record, key_fields), do: Enum.map(key_fields, &Map.get(record, &1))

  defp records_for(index, keys) do
    Enum.map(keys, &Map.fetch!(index, &1))
  end

  defp diff_records(config, left_record, right_record) do
    config
    |> fields_to_compare(left_record, right_record)
    |> Enum.reduce(%{}, fn field, acc ->
      rule = Map.get(config.rules, field, :exact)
      left_value = Map.get(left_record, field)
      right_value = Map.get(right_record, field)

      if rule == :ignore or equal?(rule, left_value, right_value) do
        acc
      else
        Map.put(acc, field, %{left: left_value, right: right_value, rule: rule})
      end
    end)
  end

  defp fields_to_compare(%__MODULE__{compare_fields: nil} = config, left_record, right_record) do
    left_record
    |> Map.keys()
    |> Enum.concat(Map.keys(right_record))
    |> Enum.uniq()
    |> Enum.reject(&(&1 in config.key_fields))
  end

  defp fields_to_compare(%__MODULE__{compare_fields: fields}, _left, _right) do
    Enum.uniq(fields)
  end

  defp equal?(:exact, left, right), do: left == right

  defp equal?({:numeric, tolerance}, left, right) when is_number(left) and is_number(right) do
    abs(left - right) <= tolerance
  end

  defp equal?(:case_insensitive, left, right) when is_binary(left) and is_binary(right) do
    normalize_string(left) == normalize_string(right)
  end

  defp equal?(_rule, left, right), do: left == right

  defp normalize_string(value) do
    value |> String.trim() |> String.downcase()
  end
end
```

Output only `validate_compare_fields` (with any `@doc`/`@spec`/`@impl` lines that belong
directly above it) — the single function, not the module.
