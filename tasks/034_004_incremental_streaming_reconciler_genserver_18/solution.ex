  @spec put_pending(state(), :left | :right, key(), stream_record()) :: state()
  defp put_pending(state, side, key, record) do
    field = pending_field(side)
    Map.put(state, field, Map.put(Map.fetch!(state, field), key, record))
  end