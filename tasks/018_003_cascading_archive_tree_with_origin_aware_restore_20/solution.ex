  defp validate_parent(_state, nil, :optional), do: :ok
  defp validate_parent(_state, nil, :required), do: {:error, :parent_not_found}

  defp validate_parent(state, parent_id, _mode) do
    case Map.fetch(state.nodes, parent_id) do
      {:ok, %{type: :folder} = parent} ->
        if live?(parent), do: :ok, else: {:error, :parent_archived}

      _other ->
        {:error, :parent_not_found}
    end
  end