  @doc """
  Returns `{:ok, entries}` describing every commit reachable from `commit_hash`
  by transitively following parent links, or `{:error, :not_found}` if the
  starting hash is unknown.

  Each entry is a map with `:hash`, `:tree`, `:parents`, `:author`, and
  `:message`. The list is ordered newest-to-oldest: the starting commit is
  first and every commit appears before all of its ancestors (a
  reverse-topological ordering).
  """
  @spec log(server(), hash()) :: {:ok, [entry()]} | {:error, :not_found}
  def log(server, commit_hash) when is_binary(commit_hash) do
    GenServer.call(server, {:log, commit_hash})
  end