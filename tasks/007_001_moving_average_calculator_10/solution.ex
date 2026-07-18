  defp put_stream(state, name, stream) do
    %{state | streams: Map.put(state.streams, name, stream)}
  end