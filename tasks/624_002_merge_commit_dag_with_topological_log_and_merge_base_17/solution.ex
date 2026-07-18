  @spec entry(hash(), map()) :: entry()
  defp entry(hash, objects) do
    %{parents: parents, tree: tree, author: author, message: message} =
      parse_commit(Map.fetch!(objects, hash))

    %{
      hash: hash,
      tree: tree,
      parents: parents,
      author: author,
      message: message
    }
  end