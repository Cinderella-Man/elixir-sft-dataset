  # Compares `left` and `right` on the given fields using `==`.
  # Missing fields are treated as nil.
  @spec diff(record(), record(), [atom()]) :: diff_map()
  defp diff(left, right, fields) do
    Enum.reduce(fields, %{}, fn field, acc ->
      lv = Map.get(left, field)
      rv = Map.get(right, field)

      if lv == rv do
        acc
      else
        Map.put(acc, field, %{left: lv, right: rv})
      end
    end)
  end