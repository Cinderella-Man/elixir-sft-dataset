  defp add_event(state, event) do
    %{state | buffer: [event | state.buffer], count: state.count + 1}
  end