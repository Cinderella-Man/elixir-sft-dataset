  @spec prepend_version(map(), String.t(), map()) :: map()
  defp prepend_version(keys, key, version) do
    Map.update(keys, key, [version], &[version | &1])
  end