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
defmodule TolerantReconciler do
  @enforce_keys [:key_fields, :compare_fields, :rules]
  defstruct [:key_fields, :compare_fields, :rules]

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
