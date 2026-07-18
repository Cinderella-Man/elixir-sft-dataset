  @doc """
  Returns the number of intervals stored in `tree`.

  Runs in constant time; every node caches the size of its own subtree.
  """
  @spec size(t()) :: non_neg_integer()
  def size(nil), do: 0
  def size(%{size: n}), do: n