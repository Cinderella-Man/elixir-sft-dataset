  def commit(server, tree_hash, parent_hash, message, author) do
    GenServer.call(server, {:commit, tree_hash, parent_hash, message, author})
  end