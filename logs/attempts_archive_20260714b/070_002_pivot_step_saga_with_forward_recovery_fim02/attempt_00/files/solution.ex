  defp compensate_all(completed, context) do
    Enum.map(completed, fn %{name: name, compensate: compensate} ->
      {name, safe_compensate(compensate, context)}
    end)
  end