  defp next_tick(state) do
    tick = state.tick + 1
    {tick, %{state | tick: tick}}
  end