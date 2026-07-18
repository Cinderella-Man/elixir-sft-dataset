  defp normalise_path(path) when is_list(path), do: path
  defp normalise_path(path) when is_tuple(path), do: Tuple.to_list(path)

  defp normalise_path(path) do
    raise ArgumentError, "key paths must be lists or tuples of atoms, got: #{inspect(path)}"
  end