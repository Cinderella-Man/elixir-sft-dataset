  defp do_delete(node, "") do
    if node.terminal, do: {%{node | terminal: false}, :ok}, else: :notfound
  end

  defp do_delete(node, word) do
    key = String.first(word)

    case Map.fetch(node.edges, key) do
      :error ->
        :notfound

      {:ok, %{label: label, child: child} = edge} ->
        if String.starts_with?(word, label) do
          case do_delete(child, drop(word, String.length(label))) do
            :notfound -> :notfound
            {new_child, :ok} -> {cleanup_edge(node, key, edge, new_child), :ok}
          end
        else
          :notfound
        end
    end
  end