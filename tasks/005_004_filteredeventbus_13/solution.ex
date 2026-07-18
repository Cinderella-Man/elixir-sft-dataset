  defp valid_path?(path) do
    Enum.all?(path, fn
      k when is_atom(k) or is_binary(k) or is_integer(k) -> true
      _ -> false
    end)
  end