  @doc """
  Inserts `interval` into `tree` and returns the updated tree.

  The original `tree` is unmodified (persistent / purely-functional).
  """
  @spec insert(t(), interval()) :: t()
  def insert(tree, {_start, _finish} = interval), do: do_insert(tree, interval)