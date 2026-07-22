  defp compensate_all(completed, context, jrev0) do
    Enum.reduce(completed, {[], jrev0}, fn %{name: name, compensate: compensate}, {acc, jrev} ->
      value = safe_compensate(compensate, context)
      {acc ++ [{name, value}], [{:compensated, name, value} | jrev]}
    end)
  end