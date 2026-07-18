  @spec empty_state() :: or_state()
  defp empty_state do
    %{entries: %{}, tombstones: MapSet.new(), clock: %{}}
  end