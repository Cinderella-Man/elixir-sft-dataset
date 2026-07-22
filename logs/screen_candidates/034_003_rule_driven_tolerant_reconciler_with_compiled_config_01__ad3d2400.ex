defmodule TolerantReconciler do
  @moduledoc """
  Reconciles two lists of record maps using per-field comparison rules rather than
  strict equality.

  The module is split into two stages:

    * `compile/1` validates a keyword list of options and produces an opaque
      configuration value.
    * `run/3` executes the reconciliation against two lists of maps, producing a
      report of matched pairs (with their per-field differences) and the records
      that appear on only one side.

  Records are paired by exact equality on the composite key given by `:key_fields`.
  Comparison rules never apply to key fields. Once a pair is formed, each compared
  field is evaluated under its rule:

    * `:exact` — values differ unless `left == right`.
    * `{:numeric, tolerance}` — when both values are numbers they are equal if
      `abs(left - right) <= tolerance`; otherwise `==` is used.
    * `:case_insensitive` — when both values are binaries they are equal if their
      trimmed, downcased forms are equal; otherwise `==` is used.
    * `:ignore` — the field is never compared and never appears in a differences map.

  `field_summary/1` turns a report into a tally of how many matched pairs differed
  on each field.

  ## Example

      iex> {:ok, config} =
      ...>   TolerantReconciler.compile(
      ...>     key_fields: [:id],
      ...>     rules: [amount: {:numeric, 0.01}, name: :case_insensitive]
      ...>   )
      iex> left = [%{id: 1, amount: 10.0, name: "Ada"}]
      iex> right = [%{id: 1, amount: 10.005, name: " ada "}]
      iex> report = TolerantReconciler.run(config, left, right)
      iex> TolerantReconciler.field_summary(report)
      %{}

  All functions are pure: no processes, no side effects, no external dependencies.
  """

  @typedoc "A rule describing how a single field is compared."
  @type rule :: :exact | :ignore | :case_insensitive | {:numeric, number()}

  @typedoc "An opaque configuration produced by `compile/1`."
  @opaque config :: %{
            key_fields: [atom()],
            compare_fields: [atom()] | nil,
            rules: %{optional(atom()) => rule()}
          }

  @typedoc "A single record: a map keyed by field name."
  @type record :: map()

  @typedoc "The differences found for one matched pair."
  @type diff_map :: %{optional(atom()) => %{left: term(), right: term(), rule: rule()}}

  @typedoc "One matched pair and its differences."
  @type matched_pair :: %{left: record(), right: record(), differences: diff_map()}

  @typedoc "The report returned by `run/3`."
  @type report :: %{
          matched: [matched_pair()],
          only_in_left: [record()],
          only_in_right: [record()]
        }

  @typedoc "Reasons `compile/1` can reject its options."
  @type compile_error ::
          :missing_key_fields
          | :invalid_key_fields
          | :invalid_compare_fields
          | :invalid_rules
          | {:invalid_rule, atom()}

  @doc """
  Validates reconciliation options and returns an opaque configuration.

  ## Options

    * `:key_fields` (required) — non-empty list of atoms forming the composite key.
    * `:compare_fields` (optional) — list of atoms to compare on matched pairs. When
      omitted or `nil`, every field present in either record of a pair is compared,
      minus the key fields.
    * `:rules` (optional, default `[]`) — keyword list of `field => rule`. Compared
      fields with no entry use `:exact`.

  Returns `{:ok, config}` or `{:error, reason}` where `reason` is one of
  `:missing_key_fields`, `:invalid_key_fields`, `:invalid_compare_fields`,
  `:invalid_rules` or `{:invalid_rule, field}`.

  ## Examples

      iex> TolerantReconciler.compile(key_fields: [:id])
      ...> |> elem(0)
      :ok

      iex> TolerantReconciler.compile([])
      {:error, :missing_key_fields}

      iex> TolerantReconciler.compile(key_fields: [:id], rules: [amount: {:numeric, -1}])
      {:error, {:invalid_rule, :amount}}
  """
  @spec compile(keyword()) :: {:ok, config()} | {:error, compile_error()}
  def compile(opts) when is_list(opts) do
    with :ok <- validate_opts_shape(opts),
         {:ok, key_fields} <- validate_key_fields(opts),
         {:ok, compare_fields} <- validate_compare_fields(opts),
         {:ok, rules} <- validate_rules(opts) do
      {:ok,
       %{
         key_fields: key_fields,
         compare_fields: compare_fields,
         rules: rules
       }}
    end
  end

  def compile(_opts), do: {:error, :missing_key_fields}

  @doc """
  Reconciles `left` against `right` using a configuration from `compile/1`.

  Records are indexed by the tuple of their key-field values (a missing key field is
  read as `nil`); when a key repeats within one list the last record wins. Keys found
  on both sides become matched pairs whose compared fields are evaluated under their
  rules; the remaining records land in `:only_in_left` or `:only_in_right`.

  Returns `%{matched: [...], only_in_left: [...], only_in_right: [...]}`. Result order
  is unspecified.

  ## Examples

      iex> {:ok, config} = TolerantReconciler.compile(key_fields: [:id])
      iex> report = TolerantReconciler.run(config, [%{id: 1, v: 1}], [%{id: 1, v: 2}])
      iex> [%{differences: diffs}] = report.matched
      iex> diffs
      %{v: %{left: 1, right: 2, rule: :exact}}
  """
  @spec run(config(), [record()], [record()]) :: report()
  def run(%{key_fields: key_fields} = config, left, right)
      when is_list(left) and is_list(right) do
    left_index = index_by_key(left, key_fields)
    right_index = index_by_key(right, key_fields)

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
          differences: compare_pair(config, left_record, right_record)
        }
      end)

    %{
      matched: matched,
      only_in_left: exclusive_records(left_index, right_keys),
      only_in_right: exclusive_records(right_index, left_keys)
    }
  end

  @doc """
  Counts, per field, how many matched pairs in `report` differed on that field.

  Fields that never differed are omitted, so a fully clean report yields `%{}`.

  ## Examples

      iex> {:ok, config} = TolerantReconciler.compile(key_fields: [:id])
      iex> config
      ...> |> TolerantReconciler.run([%{id: 1, v: 1}], [%{id: 1, v: 2}])
      ...> |> TolerantReconciler.field_summary()
      %{v: 1}
  """
  @spec field_summary(report()) :: %{optional(atom()) => pos_integer()}
  def field_summary(%{matched: matched}) when is_list(matched) do
    Enum.reduce(matched, %{}, fn %{differences: differences}, acc ->
      Enum.reduce(Map.keys(differences), acc, fn field, inner ->
        Map.update(inner, field, 1, &(&1 + 1))
      end)
    end)
  end

  # ----------------------------------------------------------------------------
  # compile/1 validation
  # ----------------------------------------------------------------------------

  @spec validate_opts_shape(keyword()) :: :ok | {:error, compile_error()}
  defp validate_opts_shape(opts) do
    if Keyword.keyword?(opts), do: :ok, else: {:error, :missing_key_fields}
  end

  @spec validate_key_fields(keyword()) :: {:ok, [atom()]} | {:error, compile_error()}
  defp validate_key_fields(opts) do
    case Keyword.fetch(opts, :key_fields) do
      :error ->
        {:error, :missing_key_fields}

      {:ok, key_fields} ->
        if non_empty_atom_list?(key_fields) do
          {:ok, key_fields}
        else
          {:error, :invalid_key_fields}
        end
    end
  end

  @spec validate_compare_fields(keyword()) :: {:ok, [atom()] | nil} | {:error, compile_error()}
  defp validate_compare_fields(opts) do
    case Keyword.fetch(opts, :compare_fields) do
      :error -> {:ok, nil}
      {:ok, nil} -> {:ok, nil}
      {:ok, fields} -> validate_compare_field_list(fields)
    end
  end

  @spec validate_compare_field_list(term()) :: {:ok, [atom()]} | {:error, compile_error()}
  defp validate_compare_field_list(fields) do
    if atom_list?(fields) do
      {:ok, fields}
    else
      {:error, :invalid_compare_fields}
    end
  end

  @spec validate_rules(keyword()) ::
          {:ok, %{optional(atom()) => rule()}} | {:error, compile_error()}
  defp validate_rules(opts) do
    rules = Keyword.get(opts, :rules, [])

    cond do
      not is_list(rules) -> {:error, :invalid_rules}
      not Keyword.keyword?(rules) -> {:error, :invalid_rules}
      true -> build_rule_map(rules)
    end
  end

  @spec build_rule_map(keyword()) :: {:ok, %{optional(atom()) => rule()}} | {:error, compile_error()}
  defp build_rule_map(rules) do
    Enum.reduce_while(rules, {:ok, %{}}, fn {field, rule}, {:ok, acc} ->
      if valid_rule?(rule) do
        {:cont, {:ok, Map.put(acc, field, rule)}}
      else
        {:halt, {:error, {:invalid_rule, field}}}
      end
    end)
  end

  @spec valid_rule?(term()) :: boolean()
  defp valid_rule?(:exact), do: true
  defp valid_rule?(:case_insensitive), do: true
  defp valid_rule?(:ignore), do: true
  defp valid_rule?({:numeric, tolerance}) when is_number(tolerance), do: tolerance >= 0
  defp valid_rule?(_other), do: false

  @spec non_empty_atom_list?(term()) :: boolean()
  defp non_empty_atom_list?([_ | _] = list), do: atom_list?(list)
  defp non_empty_atom_list?(_other), do: false

  @spec atom_list?(term()) :: boolean()
  defp atom_list?(list) when is_list(list), do: Enum.all?(list, &is_atom/1)
  defp atom_list?(_other), do: false

  # ----------------------------------------------------------------------------
  # run/3 helpers
  # ----------------------------------------------------------------------------

  @spec index_by_key([record()], [atom()]) :: %{optional(tuple()) => record()}
  defp index_by_key(records, key_fields) do
    Enum.reduce(records, %{}, fn record, acc ->
      Map.put(acc, key_of(record, key_fields), record)
    end)
  end

  @spec key_of(record(), [atom()]) :: tuple()
  defp key_of(record, key_fields) do
    key_fields
    |> Enum.map(&Map.get(record, &1))
    |> List.to_tuple()
  end

  @spec exclusive_records(%{optional(tuple()) => record()}, MapSet.t()) :: [record()]
  defp exclusive_records(index, other_keys) do
    index
    |> Enum.reject(fn {key, _record} -> MapSet.member?(other_keys, key) end)
    |> Enum.map(fn {_key, record} -> record end)
  end

  @spec compare_pair(config(), record(), record()) :: diff_map()
  defp compare_pair(config, left_record, right_record) do
    config
    |> fields_to_compare(left_record, right_record)
    |> Enum.reduce(%{}, fn field, acc ->
      rule = Map.get(config.rules, field, :exact)

      cond do
        rule == :ignore ->
          acc

        true ->
          left_value = Map.get(left_record, field)
          right_value = Map.get(right_record, field)

          if values_equal?(rule, left_value, right_value) do
            acc
          else
            Map.put(acc, field, %{left: left_value, right: right_value, rule: rule})
          end
      end
    end)
  end

  @spec fields_to_compare(config(), record(), record()) :: [atom()]
  defp fields_to_compare(%{compare_fields: nil, key_fields: key_fields}, left, right) do
    left
    |> Map.keys()
    |> Kernel.++(Map.keys(right))
    |> Enum.uniq()
    |> Enum.reject(&(&1 in key_fields))
  end

  defp fields_to_compare(%{compare_fields: fields, key_fields: key_fields}, _left, _right) do
    fields
    |> Enum.uniq()
    |> Enum.reject(&(&1 in key_fields))
  end

  @spec values_equal?(rule(), term(), term()) :: boolean()
  defp values_equal?(:exact, left, right), do: left == right

  defp values_equal?({:numeric, tolerance}, left, right)
       when is_number(left) and is_number(right) do
    abs(left - right) <= tolerance
  end

  defp values_equal?({:numeric, _tolerance}, left, right), do: left == right

  defp values_equal?(:case_insensitive, left, right) when is_binary(left) and is_binary(right) do
    normalize_string(left) == normalize_string(right)
  end

  defp values_equal?(:case_insensitive, left, right), do: left == right

  defp values_equal?(:ignore, _left, _right), do: true

  @spec normalize_string(binary()) :: binary()
  defp normalize_string(value) do
    value
    |> String.trim()
    |> String.downcase()
  end
end