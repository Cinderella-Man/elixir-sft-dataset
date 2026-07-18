  @spec windows(integer(), integer(), pos_integer()) :: [integer()]
  defp windows(start_ts, end_ts, _step) when start_ts >= end_ts, do: []

  defp windows(start_ts, end_ts, step) do
    start_ts
    |> Stream.iterate(&(&1 + step))
    |> Enum.take_while(&(&1 < end_ts))
  end