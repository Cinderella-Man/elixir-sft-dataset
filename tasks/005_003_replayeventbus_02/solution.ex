  # history is oldest-first list of {ts, event}.
  defp replay_events(_history, :none, _pid, _topic), do: :ok

  defp replay_events(history, :all, pid, topic) do
    Enum.each(history, fn {_ts, evt} -> send(pid, {:event, topic, evt}) end)
  end

  defp replay_events(history, n, pid, topic) when is_integer(n) and n > 0 do
    # Enum.take(-n) grabs the n last elements in oldest-first order.
    history
    |> Enum.take(-n)
    |> Enum.each(fn {_ts, evt} -> send(pid, {:event, topic, evt}) end)
  end

  defp replay_events(_, _, _, _), do: :ok