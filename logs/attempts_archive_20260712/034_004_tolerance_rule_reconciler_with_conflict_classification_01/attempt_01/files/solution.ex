defmodule TolerantReconciler do
  @moduledoc """
  Reconciles records between two systems using per-field comparison rules instead of
  strict equality, and classifies every matched pair by how badly it disagrees.

  Real-world reconciliation rarely finds byte-identical records: a float may be off by
  rounding, a name may differ only in case or padding. Such benign differences are
  reported as `:within_tolerance` rather than escalated to `:conflict`.

  Supported rules:

    * `:exact` — values must be equal (`==`); any difference is a conflict.
    * `{:numeric, tolerance}` — tolerable when both values are numbers and
      `abs(left - right) <= tolerance`.
    * `:case_insensitive` — tolerable when both values are binaries that are equal after
      trimming leading/trailing whitespace and downcasing.

  Fields without an explicit rule default to `:exact`. The module is pure: it spawns no
  processes, performs no I/O, and depends only on the Elixir standard library.
  """

  @type field :: atom()
  @type rule :: :exact | :case_insensitive | {:numeric, number()}
  @type record :: %{optional(field()) => term()}
  @type field_status :: :within_tolerance | :conflict
  @type pair_status :: :identical | :within_tolerance | :conflict
  @type field_diff :: %{left: term(), right: term(), status: field_status()}
  @type diff_map :: %{optional(field()) => field_diff()}
  @type key_map :: %{optional(field()) => term()}
  @type entry :: %{key: key_map(), left: record(), right: record(), differences: diff_map()}
  @type result :: %{
          identical: [entry()],
          within_tolerance: [entry()],
          conflicts: [entry()],
          only_in_left: [record()],
          only_in_right: [record()]
        }

  @doc """
  Compares two maps field by field and returns `{status, diff_map}`.

  Options:

    * `:rules` — a map or keyword list of `field => rule`; fields without a rule use
      `:exact`.
    * `:ignore_fields` — a list of atoms excluded from comparison entirely (default `[]`).

  The diff map contains only differing fields, each as
  `%{left: value, right: value, status: :within_tolerance | :conflict}`.

  The status is `:identical` when the diff map is empty, `:conflict` when any differing
  field conflicts, and `:within_tolerance` otherwise.

  ## Examples

      iex> TolerantReconciler.diff_pair(%{a: 1}, %{a: 1}, [])
      {:identical, %{}}

  """
  @spec diff_pair(record(), record(), keyword()) :: {pair_status(), diff_map()}
  def diff_pair(left, right, opts \\ []) when is_map(left) and is_map(right) and is_list(opts) do
    rules = normalize_rules(Keyword.get(opts, :rules, %{}))
    ignored = MapSet.new(Keyword.get(opts, :ignore_fields, []))

    diff = build_diff(left, right, rules, ignored)
    {status_of(diff), diff}
  end

  @doc """
  Reconciles two lists of maps by a composite key, bucketing the outcome.

  Options:

    * `:key_fields` — required, a non-empty list of atoms forming the composite key.
      A missing or invalid value raises `ArgumentError`.
    * `:rules` — as in `diff_pair/3`.
    * `:ignore_fields` — extra fields excluded from comparison; key fields are always
      excluded whether or not they are listed.

  Returns a map with the keys `:identical`, `:within_tolerance`, `:conflicts`,
  `:only_in_left` and `:only_in_right`. When a key repeats on one side, the last record
  with that key in the input list wins.
  """
  @spec reconcile_all([record()], [record()], keyword()) :: result()
  def reconcile_all(left, right, opts \\ [])
      when is_list(left) and is_list(right) and is_list(opts) do
    key_fields = validate_key_fields(Keyword.get(opts, :key_fields))

    ignored =
      opts
      |> Keyword.get(:ignore_fields, [])
      |> Enum.concat(key_fields)

    pair_opts = [rules: Keyword.get(opts, :rules, %{}), ignore_fields: ignored]

    left_index = index_by_key(left, key_fields)
    right_index = index_by_key(right, key_fields)

    left_keys = left_index |> Map.keys() |> MapSet.new()
    right_keys = right_index |> Map.keys() |> MapSet.new()
    matched_keys = MapSet.intersection(left_keys, right_keys)

    base = %{
      identical: [],
      within_tolerance: [],
      conflicts: [],
      only_in_left: pick(left_index, MapSet.difference(left_keys, right_keys)),
      only_in_right: pick(right_index, MapSet.difference(right_keys, left_keys))
    }

    Enum.reduce(matched_keys, base, fn key, acc ->
      left_record = Map.fetch!(left_index, key)
      right_record = Map.fetch!(right_index, key)
      {status, differences} = diff_pair(left_record, right_record, pair_opts)

      entry = %{
        key: key,
        left: left_record,
        right: right_record,
        differences: differences
      }

      Map.update!(acc, bucket_for(status), fn entries -> [entry | entries] end)
    end)
  end

  @doc """
  Counts the entries in a `reconcile_all/3` result.

  Returns a map with `:identical`, `:within_tolerance`, `:conflicts`, `:only_in_left`,
  `:only_in_right` and `:matched` (the sum of the first three).
  """
  @spec summary(result()) :: %{
          identical: non_neg_integer(),
          within_tolerance: non_neg_integer(),
          conflicts: non_neg_integer(),
          only_in_left: non_neg_integer(),
          only_in_right: non_neg_integer(),
          matched: non_neg_integer()
        }
  def summary(result) when is_map(result) do
    identical = count(result, :identical)
    within_tolerance = count(result, :within_tolerance)
    conflicts = count(result, :conflicts)

    %{
      identical: identical,
      within_tolerance: within_tolerance,
      conflicts: conflicts,
      only_in_left: count(result, :only_in_left),
      only_in_right: count(result, :only_in_right),
      matched: identical + within_tolerance + conflicts
    }
  end

  # -- internals ------------------------------------------------------------------

  defp build_diff(left, right, rules, ignored) do
    left
    |> Map.keys()
    |> Enum.concat(Map.keys(right))
    |> Enum.uniq()
    |> Enum.reject(fn field -> MapSet.member?(ignored, field) end)
    |> Enum.reduce(%{}, fn field, acc ->
      left_value = Map.get(left, field)
      right_value = Map.get(right, field)

      if left_value == right_value do
        acc
      else
        rule = Map.get(rules, field, :exact)
        status = field_status(rule, left_value, right_value)
        Map.put(acc, field, %{left: left_value, right: right_value, status: status})
      end
    end)
  end

  defp field_status({:numeric, tolerance}, left, right)
       when is_number(left) and is_number(right) and is_number(tolerance) do
    if abs(left - right) <= tolerance, do: :within_tolerance, else: :conflict
  end

  defp field_status(:case_insensitive, left, right) when is_binary(left) and is_binary(right) do
    if normalize_binary(left) == normalize_binary(right), do: :within_tolerance, else: :conflict
  end

  defp field_status(_rule, _left, _right), do: :conflict

  defp normalize_binary(value), do: value |> String.trim() |> String.downcase()

  defp status_of(diff) when map_size(diff) == 0, do: :identical

  defp status_of(diff) do
    conflict? =
      Enum.any?(diff, fn {_field, info} -> Map.get(info, :status) == :conflict end)

    if conflict?, do: :conflict, else: :within_tolerance
  end

  defp normalize_rules(rules) when is_map(rules), do: rules

  defp normalize_rules(rules) when is_list(rules) do
    if Keyword.keyword?(rules) do
      Map.new(rules)
    else
      raise ArgumentError, ":rules must be a map or keyword list of field => rule"
    end
  end

  defp normalize_rules(_other) do
    raise ArgumentError, ":rules must be a map or keyword list of field => rule"
  end

  defp validate_key_fields([_ | _] = key_fields) do
    if Enum.all?(key_fields, fn field -> is_atom(field) end) do
      key_fields
    else
      raise ArgumentError, ":key_fields must be a non-empty list of atoms"
    end
  end

  defp validate_key_fields(_other) do
    raise ArgumentError, ":key_fields is required and must be a non-empty list of atoms"
  end

  defp index_by_key(records, key_fields) do
    Enum.reduce(records, %{}, fn record, acc ->
      Map.put(acc, key_of(record, key_fields), record)
    end)
  end

  defp key_of(record, key_fields) do
    Map.new(key_fields, fn field -> {field, Map.get(record, field)} end)
  end

  defp pick(index, keys) do
    Enum.map(keys, fn key -> Map.fetch!(index, key) end)
  end

  defp bucket_for(:identical), do: :identical
  defp bucket_for(:within_tolerance), do: :within_tolerance
  defp bucket_for(:conflict), do: :conflicts

  defp count(result, bucket) do
    result |> Map.get(bucket, []) |> length()
  end
end
