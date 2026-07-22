  defp do_insert(node, "") do
    if node.terminal, do: {node, 0}, else: {%{node | terminal: true}, 1}
  end

  defp do_insert(node, word) do
    key = String.first(word)

    case Map.fetch(node.edges, key) do
      :error ->
        leaf = %{edges: %{}, terminal: true}
        edge = %{label: word, child: leaf}
        {%{node | edges: Map.put(node.edges, key, edge)}, 1}

      {:ok, %{label: label, child: child} = edge} ->
        cp = common_prefix(label, word)
        plen = String.length(cp)
        llen = String.length(label)
        wlen = String.length(word)

        cond do
          # whole edge label is consumed — descend into the child
          plen == llen ->
            {new_child, added} = do_insert(child, drop(word, plen))
            new_edge = %{edge | child: new_child}
            {%{node | edges: Map.put(node.edges, key, new_edge)}, added}

          # the word is a proper prefix of the edge label — split the edge
          plen == wlen ->
            suffix = drop(label, plen)
            old_edge = %{label: suffix, child: child}
            mid = %{edges: %{String.first(suffix) => old_edge}, terminal: true}
            {%{node | edges: Map.put(node.edges, key, %{label: cp, child: mid})}, 1}

          # partial overlap — branch into a fresh intermediate node
          true ->
            label_suffix = drop(label, plen)
            word_suffix = drop(word, plen)
            old_edge = %{label: label_suffix, child: child}
            new_leaf = %{edges: %{}, terminal: true}
            new_edge = %{label: word_suffix, child: new_leaf}

            mid = %{
              edges: %{
                String.first(label_suffix) => old_edge,
                String.first(word_suffix) => new_edge
              },
              terminal: false
            }

            {%{node | edges: Map.put(node.edges, key, %{label: cp, child: mid})}, 1}
        end
    end
  end