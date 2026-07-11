  @spec fold(acc() | nil, integer(), number()) :: acc()
  defp fold(nil, timestamp, value) do
    %{
      count: 1,
      sum: value,
      min: value,
      max: value,
      first: value,
      last: value,
      first_ts: timestamp,
      last_ts: timestamp
    }
  end

  defp fold(acc, timestamp, value) do
    {first, first_ts} =
      if timestamp < acc.first_ts do
        {value, timestamp}
      else
        {acc.first, acc.first_ts}
      end

    {last, last_ts} =
      if timestamp >= acc.last_ts do
        {value, timestamp}
      else
        {acc.last, acc.last_ts}
      end

    %{
      count: acc.count + 1,
      sum: acc.sum + value,
      min: min(acc.min, value),
      max: max(acc.max, value),
      first: first,
      last: last,
      first_ts: first_ts,
      last_ts: last_ts
    }
  end