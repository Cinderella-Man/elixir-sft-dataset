  # Drops `kpath` and every provenance entry nested beneath it, so a subtree that a
  # higher layer replaced leaves no stale descendant paths behind.
  defp prune_subtree(pr, kpath) do
    depth = length(kpath)

    Map.reject(pr, fn {path, _name} ->
      is_list(path) and Enum.take(path, depth) == kpath
    end)
  end