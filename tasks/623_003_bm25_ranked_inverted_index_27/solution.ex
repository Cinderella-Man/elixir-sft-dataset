  @doc """
  Returns up to `limit` vocabulary terms that start with `prefix`
  (case-insensitive), ordered by document frequency descending.
  """
  @spec suggest(GenServer.server(), String.t(), pos_integer()) :: [String.t()]
  def suggest(server, prefix, limit \\ 10) do
    GenServer.call(server, {:suggest, prefix, limit})
  end