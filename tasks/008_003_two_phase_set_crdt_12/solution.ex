  @spec empty_state() :: tp_state()
  defp empty_state, do: %{added: MapSet.new(), removed: MapSet.new()}