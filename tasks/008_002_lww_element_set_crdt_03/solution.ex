  # Merges two timestamp maps by taking the per-element maximum.
  @spec merge_ts_maps(ts_map(), ts_map()) :: ts_map()
  defp merge_ts_maps(local, remote) do
    Map.merge(local, remote, fn _element, l_ts, r_ts -> max(l_ts, r_ts) end)
  end