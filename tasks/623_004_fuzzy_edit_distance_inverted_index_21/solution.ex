  @doc """
  Return the vocabulary terms within `max_distance` edit distance of `term`.

  `term` is lowercased before comparison and is not split. Results are sorted by edit
  distance ascending, breaking ties alphabetically ascending. `max_distance` defaults
  to `1`.
  """
  @spec terms_like(GenServer.server(), String.t(), non_neg_integer()) :: [String.t()]
  def terms_like(server, term, max_distance \\ 1) do
    GenServer.call(server, {:terms_like, term, max_distance})
  end