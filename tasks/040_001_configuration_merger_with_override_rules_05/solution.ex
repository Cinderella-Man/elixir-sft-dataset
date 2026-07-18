  # Accept both list paths ([:a, :b]) and tuple paths ({:a, :b}) transparently.
  defp normalise_path(path, _opt) when is_list(path), do: path
  defp normalise_path(path, _opt) when is_tuple(path), do: Tuple.to_list(path)

  defp normalise_path(path, opt) do
    raise ArgumentError,
          "Key paths in `#{inspect(opt)}` must be lists or tuples of atoms, " <>
            "got: #{inspect(path)}"
  end