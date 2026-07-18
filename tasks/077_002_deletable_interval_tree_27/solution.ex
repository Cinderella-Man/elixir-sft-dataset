  @doc """
  Inserts `interval` into `tree` and returns the updated tree.

  Both endpoints must be integers with `start <= finish`. Duplicate intervals
  are permitted; each copy is stored independently.
  """
  @spec insert(t(), interval()) :: t()
  def insert(tree, {s, f} = interval) when is_integer(s) and is_integer(f) and s <= f do
    do_insert(tree, interval)
  end