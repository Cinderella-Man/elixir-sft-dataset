  defp path_present?(_map, []), do: true

  defp path_present?(map, [k | rest]) when is_map(map) do
    case Map.fetch(map, k) do
      {:ok, v} -> path_present?(v, rest)
      :error -> false
    end
  end

  defp path_present?(_map, _path), do: false