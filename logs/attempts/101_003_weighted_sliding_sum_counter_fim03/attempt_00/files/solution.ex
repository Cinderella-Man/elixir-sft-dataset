  @spec schedule_cleanup(state()) :: state()
  defp schedule_cleanup(%{cleanup_interval_ms: :infinity} = state), do: state

  defp schedule_cleanup(state) do
    Process.send_after(self(), :cleanup, state.cleanup_interval_ms)
    state
  end