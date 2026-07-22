  defp parse_commit(content) do
    case String.split(content, "\n") do
      ["commit", "tree " <> tree, "parent " <> parent | _rest] ->
        parent = if parent == "nil", do: nil, else: parent
        {:ok, %{tree: tree, parent: parent}}

      _other ->
        :error
    end
  end