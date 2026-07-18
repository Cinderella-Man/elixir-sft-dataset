  @doc """
  Returns up to `limit` vocabulary terms starting with `prefix`.

  Terms are sorted by document frequency descending (ties broken
  alphabetically). The `prefix` is lowercased before lookup.
  """
  @spec suggest(GenServer.server(), String.t(), non_neg_integer()) :: [String.t()]
  def suggest(server, prefix, limit \\ 10) do
    GenServer.call(server, {:suggest, prefix, limit})
  end