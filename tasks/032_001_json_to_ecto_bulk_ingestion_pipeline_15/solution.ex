  @spec timestamps_equal?(term(), term()) :: boolean()
  defp timestamps_equal?(nil, _), do: false
  defp timestamps_equal?(_, nil), do: false

  defp timestamps_equal?(%NaiveDateTime{} = a, %NaiveDateTime{} = b),
    do: abs(NaiveDateTime.diff(a, b, :second)) <= @insert_window_seconds

  defp timestamps_equal?(%DateTime{} = a, %DateTime{} = b),
    do: abs(DateTime.diff(a, b, :second)) <= @insert_window_seconds

  defp timestamps_equal?(_, _), do: false