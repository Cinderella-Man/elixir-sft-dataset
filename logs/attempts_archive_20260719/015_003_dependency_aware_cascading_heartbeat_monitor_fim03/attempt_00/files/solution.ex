  @spec do_probe(map(), term()) ::
          {:not_found, map()} | {:ok, status(), map()}
  defp do_probe(state, name) do
    case Map.fetch(state.nodes, name) do
      :error ->
        {:not_found, state}

      {:ok, node} ->
        old_effective = compute_effective(state.nodes)
        new_node = apply_result(node, node.probe.())
        nodes = Map.put(state.nodes, name, new_node)
        new_effective = compute_effective(nodes)
        notify_changes(nodes, old_effective, new_effective)
        {:ok, Map.fetch!(new_effective, name), %{state | nodes: nodes}}
    end
  end