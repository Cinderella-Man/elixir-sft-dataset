  defp do_delete(node, []) do
    if node.weight == 0, do: :notfound, else: {%{node | weight: 0}, :ok}
  end

  defp do_delete(node, [char | rest]) do
    case Map.fetch(node.children, char) do
      :error ->
        :notfound

      {:ok, child} ->
        case do_delete(child, rest) do
          :notfound ->
            :notfound

          {new_child, :ok} ->
            if new_child.weight == 0 and map_size(new_child.children) == 0 do
              {%{node | children: Map.delete(node.children, char)}, :ok}
            else
              {%{node | children: Map.put(node.children, char, new_child)}, :ok}
            end
        end
    end
  end