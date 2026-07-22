  @spec eff(term(), map(), map()) :: {status(), map()}
  defp eff(name, nodes, memo) do
    case Map.fetch(memo, name) do
      {:ok, status} ->
        {status, memo}

      :error ->
        case Map.fetch(nodes, name) do
          :error ->
            {:up, memo}

          {:ok, node} ->
            if node.own_status == :down do
              {:down, Map.put(memo, name, :down)}
            else
              {status, memo} = deps_status(node.depends_on, nodes, memo)
              {status, Map.put(memo, name, status)}
            end
        end
    end
  end