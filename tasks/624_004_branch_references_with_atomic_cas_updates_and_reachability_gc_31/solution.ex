  @doc """
  Garbage-collects unreferenced objects, returning `{:ok, removed_count}`.

  An object is reachable if it is a branch head, an ancestor commit reachable
  by following `parent` links from a branch head, or the tree referenced by a
  reachable commit. All other stored objects are deleted.
  """
  @spec gc(GenServer.server()) :: {:ok, non_neg_integer()}
  def gc(server) do
    GenServer.call(server, :gc)
  end