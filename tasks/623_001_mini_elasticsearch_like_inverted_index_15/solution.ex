  @spec suggest(GenServer.server(), String.t(), pos_integer()) :: [String.t()]
  @doc """
  Return up to `limit` term completions for `prefix`, sorted by document
  frequency descending.
  """
  def suggest(server, prefix, limit \\ 10) do
    GenServer.call(server, {:suggest, prefix, limit})
  end