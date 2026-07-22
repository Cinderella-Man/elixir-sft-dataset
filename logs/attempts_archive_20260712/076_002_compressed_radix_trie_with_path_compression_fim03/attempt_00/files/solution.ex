  # Walk down consuming `prefix`; `acc` is the actual path string to `node`.
  defp locate(node, "", acc), do: {node, acc}

  defp locate(node, prefix, acc) do
    key = String.first(prefix)

    case Map.fetch(node.edges, key) do
      :error ->
        :nomatch

      {:ok, %{label: label, child: child}} ->
        cond do
          String.starts_with?(prefix, label) ->
            locate(child, drop(prefix, String.length(label)), acc <> label)

          String.starts_with?(label, prefix) ->
            {child, acc <> label}

          true ->
            :nomatch
        end
    end
  end