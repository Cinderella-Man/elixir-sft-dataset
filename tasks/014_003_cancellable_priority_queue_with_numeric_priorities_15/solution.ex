  defp maybe_trigger_processing(%{processing: true} = state), do: state

  defp maybe_trigger_processing(state) do
    if queue_empty?(state) do
      state
    else
      send(self(), :process_next)
      %{state | processing: true}
    end
  end