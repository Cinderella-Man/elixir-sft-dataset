  @doc """
  Returns all intervals stored in `tree` that overlap with `query`.

  Two intervals overlap when they share at least one point:
  `{s1, f1}` overlaps `{s2, f2}` iff `s1 <= f2` and `f1 >= s2`.
  """
  @spec overlapping(t(), interval()) :: [interval()]
  def overlapping(nil, _query), do: []
  def overlapping(tree, {qs, qf}), do: do_overlapping(tree, qs, qf, [])