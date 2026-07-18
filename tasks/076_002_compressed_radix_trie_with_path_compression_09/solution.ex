  defp do_member(node, ""), do: node.terminal

  defp do_member(node, word) do
    key = String.first(word)

    case Map.fetch(node.edges, key) do
      :error ->
        false

      {:ok, %{label: label, child: child}} ->
        if String.starts_with?(word, label) do
          do_member(child, drop(word, String.length(label)))
        else
          false
        end
    end
  end