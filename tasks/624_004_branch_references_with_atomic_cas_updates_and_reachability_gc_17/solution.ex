  @spec commit_refs(binary()) :: [hash]
  defp commit_refs(content) do
    case parse_commit(content) do
      {:ok, %{tree: tree, parent: parent}} ->
        refs = [tree]
        if is_nil(parent), do: refs, else: [parent | refs]

      :error ->
        []
    end
  end