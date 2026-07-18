  defp stream_for(state, name) do
    Map.get(state.streams, name, new_stream())
  end