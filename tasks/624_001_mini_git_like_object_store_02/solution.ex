defp walk_log(_state, nil, acc), do: {:ok, Enum.reverse(acc)}

defp walk_log(state, hash, acc) do
  case Map.fetch(state, hash) do
    :error when acc == [] ->
      {:error, :not_found}

    :error ->
      # Dangling parent reference — stop gracefully.
      {:ok, Enum.reverse(acc)}

    {:ok, content} ->
      parsed = parse_commit(content)

      entry = %{
        hash: hash,
        tree: parsed.tree,
        parent: parsed.parent,
        author: parsed.author,
        message: parsed.message
      }

      walk_log(state, parsed.parent, [entry | acc])
  end
end