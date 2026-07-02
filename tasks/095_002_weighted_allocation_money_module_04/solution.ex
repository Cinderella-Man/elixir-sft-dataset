  @doc """
  Splits a money value evenly among `n` parties (a positive integer).

  Equivalent to `allocate/2` with `n` equal weights.
  """
  @spec split(t(), pos_integer()) :: [t()]
  def split(%__MODULE__{} = money, n) when is_integer(n) and n > 0 do
    allocate(money, List.duplicate(1, n))
  end

  def split(%__MODULE__{}, _n) do
    raise ArgumentError, "n must be a positive integer"
  end