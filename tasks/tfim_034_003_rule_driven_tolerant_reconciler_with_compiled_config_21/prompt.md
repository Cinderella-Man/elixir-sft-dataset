# Complete the blanked test

You get a module and its ExUnit harness, minus the body of ONE `test` —
the `# TODO` marks the spot, and its name says what it must prove. Write
exactly that test so the harness passes against a correct implementation
of the module.

## Module under test

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
    case Keyword.fetch(opts, :compare_fields) do
      :error -> {:ok, nil}
      {:ok, nil} -> {:ok, nil}
      {:ok, fields} when is_list(fields) -> compare_fields_or_error(fields)
      {:ok, _other} -> {:error, :invalid_compare_fields}
    end
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

## Test harness — implement the `# TODO` test

```elixir
defmodule TolerantReconcilerTest do
  use ExUnit.Case, async: false

  defp config!(opts) do
    {:ok, config} = TolerantReconciler.compile(opts)
    config
  end

  # ---------------------------------------------------------------------------
  # compile/1 validation
  # ---------------------------------------------------------------------------

  test "compile succeeds with only key_fields" do
    assert {:ok, _config} = TolerantReconciler.compile(key_fields: [:id])
  end

  test "compile rejects missing key_fields" do
    assert TolerantReconciler.compile([]) == {:error, :missing_key_fields}
  end

  test "compile rejects empty or non-atom key_fields" do
    assert TolerantReconciler.compile(key_fields: []) == {:error, :invalid_key_fields}
    assert TolerantReconciler.compile(key_fields: ["id"]) == {:error, :invalid_key_fields}
  end

  test "compile rejects invalid compare_fields" do
    assert TolerantReconciler.compile(key_fields: [:id], compare_fields: ["name"]) ==
             {:error, :invalid_compare_fields}
  end

  test "compile accepts nil compare_fields" do
    assert {:ok, _} = TolerantReconciler.compile(key_fields: [:id], compare_fields: nil)
  end

  test "compile rejects non-keyword rules" do
    assert TolerantReconciler.compile(key_fields: [:id], rules: %{name: :exact}) ==
             {:error, :invalid_rules}
  end

  test "compile rejects an unknown rule for a field" do
    assert TolerantReconciler.compile(key_fields: [:id], rules: [name: :fuzzy]) ==
             {:error, {:invalid_rule, :name}}
  end

  test "compile rejects a numeric rule with a bad tolerance" do
    assert TolerantReconciler.compile(key_fields: [:id], rules: [amount: {:numeric, -1}]) ==
             {:error, {:invalid_rule, :amount}}

    assert TolerantReconciler.compile(key_fields: [:id], rules: [amount: {:numeric, "0.1"}]) ==
             {:error, {:invalid_rule, :amount}}
  end

  test "compile accepts all four rule kinds" do
    assert {:ok, _} =
             TolerantReconciler.compile(
               key_fields: [:id],
               rules: [
                 amount: {:numeric, 0.01},
                 name: :case_insensitive,
                 notes: :ignore,
                 status: :exact
               ]
             )
  end

  # ---------------------------------------------------------------------------
  # Matching / partitioning
  # ---------------------------------------------------------------------------

  test "partitions records into matched, only_in_left and only_in_right" do
    config = config!(key_fields: [:id])

    report =
      TolerantReconciler.run(config, [%{id: 1}, %{id: 2}], [%{id: 1}, %{id: 3}])

    assert length(report.matched) == 1
    assert report.only_in_left == [%{id: 2}]
    assert report.only_in_right == [%{id: 3}]
  end

  test "composite keys match only when all key fields are equal" do
    config = config!(key_fields: [:org_id, :user_id])

    left = [%{org_id: 1, user_id: 10}, %{org_id: 1, user_id: 20}]
    right = [%{org_id: 1, user_id: 10}, %{org_id: 2, user_id: 10}]

    report = TolerantReconciler.run(config, left, right)

    assert length(report.matched) == 1
    assert length(report.only_in_left) == 1
    assert length(report.only_in_right) == 1
  end

  test "empty inputs" do
    config = config!(key_fields: [:id])
    report = TolerantReconciler.run(config, [], [])

    assert report == %{matched: [], only_in_left: [], only_in_right: []}
  end

  # ---------------------------------------------------------------------------
  # Duplicate keys within one list
  # ---------------------------------------------------------------------------

  test "a repeated key within one list keeps only the last record with that key" do
    config = config!(key_fields: [:id])

    left = [%{id: 1, name: "first"}, %{id: 1, name: "last"}]
    right = [%{id: 1, name: "last"}]

    report = TolerantReconciler.run(config, left, right)

    [entry] = report.matched
    assert entry.left == %{id: 1, name: "last"}
    assert entry.differences == %{}
    assert report.only_in_left == []
    assert report.only_in_right == []
  end

  test "a repeated key on the right side also keeps only the last record" do
    config = config!(key_fields: [:id])

    left = [%{id: 1, name: "last"}]
    right = [%{id: 1, name: "first"}, %{id: 1, name: "last"}]

    report = TolerantReconciler.run(config, left, right)

    [entry] = report.matched
    assert entry.right == %{id: 1, name: "last"}
    assert entry.differences == %{}
  end

  test "a repeated composite key collapses to one matched pair" do
    config = config!(key_fields: [:org_id, :user_id])

    left = [
      %{org_id: 1, user_id: 10, score: 1},
      %{org_id: 1, user_id: 10, score: 2},
      %{org_id: 1, user_id: 20, score: 3}
    ]

    right = [%{org_id: 1, user_id: 10, score: 2}, %{org_id: 1, user_id: 20, score: 3}]

    report = TolerantReconciler.run(config, left, right)

    assert length(report.matched) == 2
    assert Enum.all?(report.matched, &(&1.differences == %{}))
  end

  # ---------------------------------------------------------------------------
  # Missing key fields
  # ---------------------------------------------------------------------------

  test "a record missing a key field is keyed as nil and matches an explicit nil key" do
    config = config!(key_fields: [:id])

    report = TolerantReconciler.run(config, [%{value: 7}], [%{id: nil, value: 7}])

    assert length(report.matched) == 1
    [entry] = report.matched
    assert entry.left == %{value: 7}
    assert entry.right == %{id: nil, value: 7}
    assert entry.differences == %{}
  end

  test "a nil key does not match a present key" do
    config = config!(key_fields: [:id])

    report = TolerantReconciler.run(config, [%{value: 7}], [%{id: 1, value: 7}])

    assert report.matched == []
    assert report.only_in_left == [%{value: 7}]
    assert report.only_in_right == [%{id: 1, value: 7}]
  end

  test "composite keys treat an absent key field as nil on both sides" do
    config = config!(key_fields: [:org_id, :user_id])

    left = [%{org_id: 1, note: "l"}]
    right = [%{org_id: 1, user_id: nil, note: "r"}]

    report = TolerantReconciler.run(config, left, right)

    [entry] = report.matched
    assert entry.differences == %{note: %{left: "l", right: "r", rule: :exact}}
  end

  # ---------------------------------------------------------------------------
  # Exact rule (default)
  # ---------------------------------------------------------------------------

  test "fields with no rule default to :exact and report the rule used" do
    config = config!(key_fields: [:id])

    report =
      TolerantReconciler.run(config, [%{id: 1, name: "Alice"}], [%{id: 1, name: "Alicia"}])

    [entry] = report.matched
    assert entry.differences == %{name: %{left: "Alice", right: "Alicia", rule: :exact}}
    assert entry.left == %{id: 1, name: "Alice"}
    assert entry.right == %{id: 1, name: "Alicia"}
  end

  test "identical records produce an empty differences map" do
    # TODO
  end

  test "a compared field missing from one record is treated as nil" do
    config = config!(key_fields: [:id])
    report = TolerantReconciler.run(config, [%{id: 1, score: 42}], [%{id: 1}])

    [entry] = report.matched
    assert entry.differences == %{score: %{left: 42, right: nil, rule: :exact}}
  end

  # ---------------------------------------------------------------------------
  # Numeric tolerance rule
  # ---------------------------------------------------------------------------

  test "numeric rule absorbs differences within tolerance" do
    config = config!(key_fields: [:id], rules: [amount: {:numeric, 0.01}])

    report =
      TolerantReconciler.run(config, [%{id: 1, amount: 100.0}], [%{id: 1, amount: 100.005}])

    [entry] = report.matched
    assert entry.differences == %{}
  end

  test "numeric rule reports differences beyond tolerance with the rule attached" do
    config = config!(key_fields: [:id], rules: [amount: {:numeric, 0.01}])

    report =
      TolerantReconciler.run(config, [%{id: 1, amount: 100.0}], [%{id: 1, amount: 100.5}])

    [entry] = report.matched

    assert entry.differences == %{
             amount: %{left: 100.0, right: 100.5, rule: {:numeric, 0.01}}
           }
  end

  test "numeric rule falls back to equality when a value is not a number" do
    config = config!(key_fields: [:id], rules: [amount: {:numeric, 5}])

    report = TolerantReconciler.run(config, [%{id: 1, amount: 10}], [%{id: 1, amount: nil}])

    [entry] = report.matched
    assert entry.differences == %{amount: %{left: 10, right: nil, rule: {:numeric, 5}}}
  end

  test "numeric rule with zero tolerance still matches equal numbers" do
    config = config!(key_fields: [:id], rules: [amount: {:numeric, 0}])

    report = TolerantReconciler.run(config, [%{id: 1, amount: 7}], [%{id: 1, amount: 7}])

    [entry] = report.matched
    assert entry.differences == %{}
  end

  # ---------------------------------------------------------------------------
  # Case-insensitive rule
  # ---------------------------------------------------------------------------

  test "case_insensitive rule ignores case and surrounding whitespace" do
    config = config!(key_fields: [:id], rules: [name: :case_insensitive])

    report =
      TolerantReconciler.run(config, [%{id: 1, name: "Alice"}], [%{id: 1, name: "  alice "}])

    [entry] = report.matched
    assert entry.differences == %{}
  end

  test "case_insensitive rule still reports genuinely different strings" do
    config = config!(key_fields: [:id], rules: [name: :case_insensitive])

    report =
      TolerantReconciler.run(config, [%{id: 1, name: "Alice"}], [%{id: 1, name: "Bob"}])

    [entry] = report.matched

    assert entry.differences == %{
             name: %{left: "Alice", right: "Bob", rule: :case_insensitive}
           }
  end

  test "case_insensitive rule falls back to equality for non-binaries" do
    config = config!(key_fields: [:id], rules: [name: :case_insensitive])

    report = TolerantReconciler.run(config, [%{id: 1, name: "x"}], [%{id: 1, name: nil}])

    [entry] = report.matched
    assert Map.has_key?(entry.differences, :name)
  end

  # ---------------------------------------------------------------------------
  # Ignore rule
  # ---------------------------------------------------------------------------

  test "ignore rule keeps a field out of the differences map" do
    config = config!(key_fields: [:id], rules: [synced_at: :ignore])

    report =
      TolerantReconciler.run(
        config,
        [%{id: 1, synced_at: "t1", name: "Alice"}],
        [%{id: 1, synced_at: "t2", name: "Alice"}]
      )

    [entry] = report.matched
    assert entry.differences == %{}
  end

  test "ignore rule wins even when the field is listed in compare_fields" do
    config =
      config!(key_fields: [:id], compare_fields: [:synced_at], rules: [synced_at: :ignore])

    report =
      TolerantReconciler.run(config, [%{id: 1, synced_at: "t1"}], [%{id: 1, synced_at: "t2"}])

    [entry] = report.matched
    assert entry.differences == %{}
  end

  # ---------------------------------------------------------------------------
  # compare_fields
  # ---------------------------------------------------------------------------

  test "compare_fields restricts which fields are compared" do
    config = config!(key_fields: [:id], compare_fields: [:name])

    report =
      TolerantReconciler.run(
        config,
        [%{id: 1, name: "Alice", internal: "old"}],
        [%{id: 1, name: "Alice", internal: "new"}]
      )

    [entry] = report.matched
    assert entry.differences == %{}
    assert entry.left.internal == "old"
  end

  test "with no compare_fields, key fields are excluded from the diff" do
    config = config!(key_fields: [:id])
    report = TolerantReconciler.run(config, [%{id: 1, a: 1}], [%{id: 1, a: 2}])

    [entry] = report.matched
    assert Map.keys(entry.differences) == [:a]
  end

  # ---------------------------------------------------------------------------
  # field_summary/1
  # ---------------------------------------------------------------------------

  test "field_summary counts matched pairs per differing field, omitting clean fields" do
    config = config!(key_fields: [:id], rules: [amount: {:numeric, 0.5}])

    left = [
      %{id: 1, name: "Alice", amount: 10.0, city: "NYC"},
      %{id: 2, name: "Bob", amount: 20.0, city: "LA"},
      %{id: 3, name: "Carol", amount: 30.0, city: "SF"}
    ]

    right = [
      %{id: 1, name: "Alicia", amount: 10.2, city: "NYC"},
      %{id: 2, name: "Bobby", amount: 25.0, city: "LA"},
      %{id: 3, name: "Carol", amount: 30.0, city: "SF"}
    ]

    report = TolerantReconciler.run(config, left, right)
    summary = TolerantReconciler.field_summary(report)

    # :name differs on ids 1 and 2; :amount only on id 2 (0.2 is within tolerance);
    # :city never differs so it is omitted entirely.
    assert summary == %{name: 2, amount: 1}
  end

  test "field_summary of a clean report is empty" do
    config = config!(key_fields: [:id])
    report = TolerantReconciler.run(config, [%{id: 1, a: 1}], [%{id: 1, a: 1}])

    assert TolerantReconciler.field_summary(report) == %{}
  end

  # ---------------------------------------------------------------------------
  # Integration
  # ---------------------------------------------------------------------------

  test "mixed scenario across all rule kinds" do
    config =
      config!(
        key_fields: [:ledger, :txn_id],
        rules: [amount: {:numeric, 0.01}, counterparty: :case_insensitive, memo: :ignore]
      )

    left = [
      %{ledger: "A", txn_id: 1, amount: 100.00, counterparty: "ACME Corp", memo: "x"},
      %{ledger: "A", txn_id: 2, amount: 50.00, counterparty: "Globex", memo: "y"},
      %{ledger: "B", txn_id: 1, amount: 10.00, counterparty: "Initech", memo: "z"}
    ]

    right = [
      %{ledger: "A", txn_id: 1, amount: 100.004, counterparty: "acme corp", memo: "changed"},
      %{ledger: "A", txn_id: 2, amount: 55.00, counterparty: "Globex", memo: "y"},
      %{ledger: "C", txn_id: 9, amount: 1.00, counterparty: "Hooli", memo: "w"}
    ]

    report = TolerantReconciler.run(config, left, right)

    assert length(report.matched) == 2

    assert [%{ledger: "B", txn_id: 1}] =
             Enum.map(report.only_in_left, &Map.take(&1, [:ledger, :txn_id]))

    assert [%{ledger: "C", txn_id: 9}] =
             Enum.map(report.only_in_right, &Map.take(&1, [:ledger, :txn_id]))

    clean = Enum.find(report.matched, &(&1.left.txn_id == 1))
    assert clean.differences == %{}

    dirty = Enum.find(report.matched, &(&1.left.txn_id == 2))
    assert dirty.differences == %{amount: %{left: 50.00, right: 55.00, rule: {:numeric, 0.01}}}

    assert TolerantReconciler.field_summary(report) == %{amount: 1}
  end

  test "the last duplicate record supplies the values compared under the rules" do
    config = config!(key_fields: [:id], rules: [amount: {:numeric, 0.01}])

    left = [%{id: 1, amount: 10.0}, %{id: 1, amount: 99.0}]
    right = [%{id: 1, amount: 10.0}]

    report = TolerantReconciler.run(config, left, right)

    [entry] = report.matched
    assert entry.differences == %{amount: %{left: 99.0, right: 10.0, rule: {:numeric, 0.01}}}
    assert TolerantReconciler.field_summary(report) == %{amount: 1}
  end

  test "numeric rule treats a difference exactly equal to the tolerance as equal" do
    config = config!(key_fields: [:id], rules: [amount: {:numeric, 0.5}])

    report =
      TolerantReconciler.run(config, [%{id: 1, amount: 10.0}], [%{id: 1, amount: 10.5}])

    [entry] = report.matched
    assert entry.differences == %{}
  end

  test "with no compare_fields a field present only in the right record is still compared" do
    config = config!(key_fields: [:id])

    report = TolerantReconciler.run(config, [%{id: 1}], [%{id: 1, extra: "new"}])

    [entry] = report.matched
    assert entry.differences == %{extra: %{left: nil, right: "new", rule: :exact}}
    assert TolerantReconciler.field_summary(report) == %{extra: 1}
  end

  test "compile rejects a rules list whose pairs are not keyed by atoms" do
    assert TolerantReconciler.compile(key_fields: [:id], rules: [{"name", :exact}]) ==
             {:error, :invalid_rules}

    assert TolerantReconciler.compile(key_fields: [:id], rules: [:exact]) ==
             {:error, :invalid_rules}
  end

  test "case_insensitive rule reports no difference for equal non-binary values" do
    config = config!(key_fields: [:id], rules: [name: :case_insensitive])

    report = TolerantReconciler.run(config, [%{id: 1, name: :alice}], [%{id: 1, name: :alice}])

    [entry] = report.matched
    assert entry.differences == %{}
  end

  test "numeric rule reports no difference for equal non-number values" do
    config = config!(key_fields: [:id], rules: [amount: {:numeric, 0.01}])

    report = TolerantReconciler.run(config, [%{id: 1, amount: "n/a"}], [%{id: 1, amount: "n/a"}])

    [entry] = report.matched
    assert entry.differences == %{}
    assert TolerantReconciler.field_summary(report) == %{}
  end

  test "compile rejects compare_fields that is not a list at all" do
    assert TolerantReconciler.compile(key_fields: [:id], compare_fields: :name) ==
             {:error, :invalid_compare_fields}
  end

  # ---------------------------------------------------------------------------
  # Duplicate-key last-wins tie-break (sharper)
  # ---------------------------------------------------------------------------

  test "duplicate keys on both sides each resolve to the last record with that key" do
    config = config!(key_fields: [:id])

    # Both lists repeat id 1. The pair must be built from the last record on each
    # side, so keeping the first record or emitting both would produce a different
    # diff or an extra matched entry.
    left = [%{id: 1, v: "l-first"}, %{id: 1, v: "l-last"}]
    right = [%{id: 1, v: "r-first"}, %{id: 1, v: "r-last"}]

    report = TolerantReconciler.run(config, left, right)

    assert [entry] = report.matched
    assert entry.left == %{id: 1, v: "l-last"}
    assert entry.right == %{id: 1, v: "r-last"}
    assert entry.differences == %{v: %{left: "l-last", right: "r-last", rule: :exact}}
    assert report.only_in_left == []
    assert report.only_in_right == []
  end

  # ---------------------------------------------------------------------------
  # Absent key field treated as nil (sharper)
  # ---------------------------------------------------------------------------

  test "two records each missing the same key field share the nil key and match" do
    config = config!(key_fields: [:id])

    # Neither record carries :id, so each is keyed as nil and the two pair with
    # one another; the compared field :a still differs.
    report = TolerantReconciler.run(config, [%{a: 1}], [%{a: 2}])

    assert [entry] = report.matched
    assert entry.left == %{a: 1}
    assert entry.right == %{a: 2}
    assert entry.differences == %{a: %{left: 1, right: 2, rule: :exact}}
    assert report.only_in_left == []
    assert report.only_in_right == []
  end
end
```
