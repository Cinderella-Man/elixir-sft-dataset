# Document this module

Below is a complete, working, tested Elixir module. Its behavior is correct
and must not change — but every piece of documentation has been stripped.

Add the missing documentation and typespecs:

- a `@moduledoc` that explains what the module does and how it is used,
- a `@doc` for every public function,
- a `@spec` for every public function (add `@type`s where they make the
  specs clearer).

Do not change any behavior: every function clause, guard, and expression
must keep working exactly as it does now. Do not rename anything, do not
"improve" the code, and do not add or remove functions. Give me the
complete documented module in a single file.

## The module

```elixir
defmodule MultiKeyReconciler do
  @report_keys [
    :one_to_one,
    :one_to_many,
    :many_to_one,
    :many_to_many,
    :only_in_left,
    :only_in_right
  ]

  def classify(left, right, opts) when is_list(left) and is_list(right) and is_list(opts) do
    key_fields = validate_key_fields(Keyword.get(opts, :key_fields))
    compare_fields = validate_compare_fields(Keyword.get(opts, :compare_fields))

    left_groups = group_by_key(left, key_fields)
    right_groups = group_by_key(right, key_fields)

    empty = Map.new(@report_keys, fn key -> {key, []} end)

    left_keys = left_groups |> Map.keys() |> MapSet.new()
    right_keys = right_groups |> Map.keys() |> MapSet.new()
    all_keys = MapSet.union(left_keys, right_keys)

    Enum.reduce(all_keys, empty, fn key, acc ->
      key_map = key_map(key, key_fields)

      case {Map.get(left_groups, key), Map.get(right_groups, key)} do
        {nil, rights} ->
          prepend(acc, :only_in_right, %{key: key_map, records: Enum.reverse(rights)})

        {lefts, nil} ->
          prepend(acc, :only_in_left, %{key: key_map, records: Enum.reverse(lefts)})

        {lefts, rights} ->
          classify_pair(acc, key_map, Enum.reverse(lefts), Enum.reverse(rights), %{
            key_fields: key_fields,
            compare_fields: compare_fields
          })
      end
    end)
  end

  def counts(report) when is_map(report) do
    counts = Map.new(@report_keys, fn key -> {key, length(Map.fetch!(report, key))} end)

    ambiguous = counts.one_to_many + counts.many_to_one + counts.many_to_many

    Map.put(counts, :ambiguous, ambiguous)
  end

  # --- internals -------------------------------------------------------------

  defp classify_pair(acc, key_map, [l], [r], config) do
    differences = differences(l, r, config)
    prepend(acc, :one_to_one, %{key: key_map, left: l, right: r, differences: differences})
  end

  defp classify_pair(acc, key_map, [l], rights, _config) do
    prepend(acc, :one_to_many, %{key: key_map, left: l, right: rights})
  end

  defp classify_pair(acc, key_map, lefts, [r], _config) do
    prepend(acc, :many_to_one, %{key: key_map, left: lefts, right: r})
  end

  defp classify_pair(acc, key_map, lefts, rights, _config) do
    prepend(acc, :many_to_many, %{key: key_map, left: lefts, right: rights})
  end

  defp prepend(acc, bucket, entry), do: Map.update!(acc, bucket, &[entry | &1])

  defp differences(left, right, %{key_fields: key_fields, compare_fields: compare_fields}) do
    fields = fields_to_compare(left, right, key_fields, compare_fields)

    Enum.reduce(fields, %{}, fn field, acc ->
      left_value = Map.get(left, field)
      right_value = Map.get(right, field)

      if left_value == right_value do
        acc
      else
        Map.put(acc, field, %{left: left_value, right: right_value})
      end
    end)
  end

  defp fields_to_compare(left, right, key_fields, nil) do
    left
    |> Map.keys()
    |> Enum.concat(Map.keys(right))
    |> Enum.uniq()
    |> Enum.reject(&(&1 in key_fields))
  end

  defp fields_to_compare(_left, _right, _key_fields, compare_fields), do: compare_fields

  defp group_by_key(records, key_fields) do
    Enum.reduce(records, %{}, fn record, acc ->
      key = composite_key(record, key_fields)
      Map.update(acc, key, [record], &[record | &1])
    end)
  end

  defp composite_key(record, key_fields) do
    key_fields
    |> Enum.map(&Map.get(record, &1))
    |> List.to_tuple()
  end

  defp key_map(key_tuple, key_fields) do
    key_fields
    |> Enum.zip(Tuple.to_list(key_tuple))
    |> Map.new()
  end

  defp validate_key_fields(key_fields)
       when is_list(key_fields) and key_fields != [] do
    if Enum.all?(key_fields, &is_atom/1) do
      key_fields
    else
      raise ArgumentError,
            ":key_fields must be a non-empty list of atoms, got: #{inspect(key_fields)}"
    end
  end

  defp validate_key_fields(other) do
    raise ArgumentError,
          ":key_fields must be a non-empty list of atoms, got: #{inspect(other)}"
  end

  defp validate_compare_fields(nil), do: nil

  defp validate_compare_fields(fields) when is_list(fields) do
    if Enum.all?(fields, &is_atom/1) do
      fields
    else
      raise ArgumentError,
            ":compare_fields must be a list of atoms, got: #{inspect(fields)}"
    end
  end

  defp validate_compare_fields(other) do
    raise ArgumentError, ":compare_fields must be a list of atoms, got: #{inspect(other)}"
  end
end
```
