  @spec empty_state() :: lww_state()
  defp empty_state, do: %{adds: %{}, removes: %{}}