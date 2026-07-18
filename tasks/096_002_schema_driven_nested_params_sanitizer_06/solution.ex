  defp apply_spec(value, {:list, inner}, path) do
    if is_list(value) do
      {clean, errs, _} =
        Enum.reduce(value, {[], %{}, 0}, fn item, {acc, e, i} ->
          case apply_spec(item, inner, path ++ [i]) do
            {:ok, c} -> {[c | acc], e, i + 1}
            {:error, fe} -> {acc, Map.merge(e, fe), i + 1}
          end
        end)

      if errs == %{}, do: {:ok, Enum.reverse(clean)}, else: {:error, errs}
    else
      {:error, %{path => :expected_list}}
    end
  end

  defp apply_spec(value, spec, path) when is_map(spec) do
    if is_map(value) do
      {clean, errs} = walk_map(value, spec, path)
      if errs == %{}, do: {:ok, clean}, else: {:error, errs}
    else
      {:error, %{path => :expected_map}}
    end
  end

  defp apply_spec(value, type, path) when is_atom(type) do
    case sanitize_field(type, value) do
      {:ok, v} -> {:ok, v}
      {:error, reason} -> {:error, %{path => reason}}
    end
  end