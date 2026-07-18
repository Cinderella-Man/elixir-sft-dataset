  defp check_parent_live(_state, %{parent_id: nil}), do: :ok

  defp check_parent_live(state, node) do
    case Map.fetch(state.nodes, node.parent_id) do
      {:ok, parent} -> if live?(parent), do: :ok, else: {:error, :parent_archived}
      :error -> :ok
    end
  end