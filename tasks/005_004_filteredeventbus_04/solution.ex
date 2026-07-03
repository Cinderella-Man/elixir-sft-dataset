  defp valid_clause?({op, path, _val})
       when op in [:eq, :neq, :gt, :lt, :gte, :lte] and is_list(path) do
    valid_path?(path)
  end

  defp valid_clause?({:in, path, list}) when is_list(path) and is_list(list) do
    valid_path?(path)
  end

  defp valid_clause?({:exists, path}) when is_list(path), do: valid_path?(path)

  defp valid_clause?({:any, subs}) when is_list(subs) and subs != [] do
    Enum.all?(subs, &valid_clause?/1)
  end

  defp valid_clause?({:none, subs}) when is_list(subs) and subs != [] do
    Enum.all?(subs, &valid_clause?/1)
  end

  defp valid_clause?(_), do: false