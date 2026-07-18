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