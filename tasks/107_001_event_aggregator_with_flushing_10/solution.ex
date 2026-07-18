  defp start_timer(state) do
    state = clear_timer(state)
    ref = make_ref()
    timer = Process.send_after(self(), {:flush, ref}, state.interval_ms)
    %{state | timer: timer, timer_ref: ref}
  end