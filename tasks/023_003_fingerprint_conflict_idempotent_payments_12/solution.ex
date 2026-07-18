  # Arms the next periodic purge (when enabled) and returns the state unchanged,
  # so it can be threaded through `init/1` and `handle_info/2`.
  defp schedule_cleanup(%{cleanup_interval_ms: :infinity} = state), do: state

  defp schedule_cleanup(%{cleanup_interval_ms: interval} = state) when is_integer(interval) do
    Process.send_after(self(), :cleanup, interval)
    state
  end