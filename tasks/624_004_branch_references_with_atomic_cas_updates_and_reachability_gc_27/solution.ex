  @doc """
  Creates and stores a commit object referencing `tree_hash` with parent
  `parent_hash` (or `nil` for a root commit), along with `message` and
  `author`. Returns `{:ok, commit_hash}`. Deterministic: identical arguments
  always produce the same commit hash.
  """
  @spec commit(GenServer.server(), hash, hash | nil, String.t(), String.t()) :: {:ok, hash}
  def commit(server, tree_hash, parent_hash, message, author)
      when is_binary(tree_hash) and (is_binary(parent_hash) or is_nil(parent_hash)) and
             is_binary(message) and is_binary(author) do
    GenServer.call(server, {:commit, tree_hash, parent_hash, message, author})
  end