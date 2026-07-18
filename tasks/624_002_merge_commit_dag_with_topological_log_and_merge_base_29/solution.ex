  @doc """
  Creates a commit object and stores it, returning `{:ok, commit_hash}`.

  `tree_hash` references an already-stored object. `parents` is a list of
  parent commit hashes (`[]` for a root commit, one element for an ordinary
  commit, two or more for a merge commit). `message` and `author` are strings.

  Serialization is deterministic: identical `tree_hash`, `parents` (in the same
  order), `message`, and `author` always yield the same commit hash, and any
  difference — including different parents — yields a different hash.
  """
  @spec commit(server(), hash(), [hash()], String.t(), String.t()) :: {:ok, hash()}
  def commit(server, tree_hash, parents, message, author)
      when is_binary(tree_hash) and is_list(parents) and is_binary(message) and
             is_binary(author) do
    GenServer.call(server, {:commit, tree_hash, parents, message, author})
  end