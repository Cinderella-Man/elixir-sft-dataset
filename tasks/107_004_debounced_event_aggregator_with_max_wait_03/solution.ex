defp flush(%{count: 0} = state), do: state

defp flush(state) do
  batch = Enum.reverse(state.buffer)
  state.on_flush.(batch)

  if state.idle_timer, do: Process.cancel_timer(state.idle_timer)
  if state.max_timer, do: Process.cancel_timer(state.max_timer)

  %{state | buffer: [], count: 0, gen: nil, idle_timer: nil, max_timer: nil}
end