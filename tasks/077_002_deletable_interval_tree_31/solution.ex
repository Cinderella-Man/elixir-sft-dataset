  @doc """
  Returns all stored intervals that contain the integer `point`
  (that is, `start <= point <= finish`).
  """
  @spec enclosing(t(), integer()) :: [interval()]
  def enclosing(nil, _point), do: []
  def enclosing(tree, point) when is_integer(point), do: do_enclosing(tree, point, [])