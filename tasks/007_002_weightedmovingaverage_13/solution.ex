  defp maybe_grow_max_period(%{max_period: mp} = stream, period) when period > mp,
    do: %{stream | max_period: period}

  defp maybe_grow_max_period(stream, _period), do: stream