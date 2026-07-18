  defp fetch_live(state, id) do
    case Map.fetch(state.nodes, id) do
      {:ok, node} -> if live?(node), do: {:ok, node}, else: {:error, :not_found}
      :error -> {:error, :not_found}
    end
  end