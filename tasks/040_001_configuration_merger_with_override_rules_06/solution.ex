  # Check whether a key path is in the locked set.
  defp locked?(key_path, %{locked_paths: locked_paths}) do
    key_path in locked_paths
  end