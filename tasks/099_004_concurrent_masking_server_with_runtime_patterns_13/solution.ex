  defp sensitive?(state, key) do
    MapSet.member?(state.sensitive, normalize_key(key))
  end