  @spec update_key(map(), String.t(), [map()]) :: map()
  defp update_key(keys, key, []), do: Map.delete(keys, key)
  defp update_key(keys, key, versions), do: Map.put(keys, key, versions)