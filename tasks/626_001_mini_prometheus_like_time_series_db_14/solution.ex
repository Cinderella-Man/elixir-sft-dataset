  defp build_windows(start_ts, end_ts, step_ms) do
    Stream.iterate(start_ts, &(&1 + step_ms))
    |> Stream.take_while(&(&1 < end_ts))
    |> Enum.to_list()
  end