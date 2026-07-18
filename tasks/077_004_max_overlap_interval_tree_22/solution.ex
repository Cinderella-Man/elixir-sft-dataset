  @doc """
  Inserts the closed interval `[start, finish]` and returns the updated tree.

  The original `tree` is unmodified. `start <= finish` is assumed.
  """
  @spec insert(t(), interval()) :: t()
  def insert(tree, {start, finish}) do
    tree
    |> bump(start, 1)
    |> bump(finish + 1, -1)
  end