  defp clear_timer(%{timer: nil} = state), do: state

  defp clear_timer(state) do
    Process.cancel_timer(state.timer)
    %{state | timer: nil, timer_ref: nil}
  end