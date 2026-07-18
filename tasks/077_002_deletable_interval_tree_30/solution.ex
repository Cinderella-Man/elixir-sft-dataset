  @doc """
  Returns all stored intervals that overlap the query range `{start, finish}`.

  Two intervals overlap when they share at least one point, so touching
  intervals are included.
  """
  @spec overlapping(t(), interval()) :: [interval()]
  def overlapping(nil, _query), do: []
  def overlapping(tree, {qs, qf}), do: do_overlapping(tree, qs, qf, [])