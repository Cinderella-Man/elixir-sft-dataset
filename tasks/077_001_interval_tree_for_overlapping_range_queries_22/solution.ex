  @doc """
  Returns all intervals stored in `tree` that contain `point`.

  An interval `{s, f}` contains `point` iff `s <= point <= f`.
  """
  @spec enclosing(t(), integer()) :: [interval()]
  def enclosing(nil, _point), do: []
  def enclosing(tree, point), do: do_enclosing(tree, point, [])