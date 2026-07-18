  defp normalise_path(path) when is_list(path), do: path
  defp normalise_path(path) when is_tuple(path), do: Tuple.to_list(path)