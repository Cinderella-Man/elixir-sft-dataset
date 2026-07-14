  @doc """
  Splits a money value evenly among `n` parties (a positive integer), working
  in whole minor units. The remainder is given to the first
  `Integer.mod(amount, n)` parties so shares sum back to the original — for
  negative amounts too, which is why the division must floor rather than
  truncate toward zero.
  """
  @spec split(t(), pos_integer()) :: [t()]
  def split(%__MODULE__{amount: amount, currency: currency}, n)
      when is_integer(n) and n > 0 do
    base = Integer.floor_div(amount, n)
    remainder = Integer.mod(amount, n)

    Enum.map(0..(n - 1), fn i ->
      cents = if i < remainder, do: base + 1, else: base
      %__MODULE__{amount: cents, currency: currency}
    end)
  end

  def split(%__MODULE__{}, _n) do
    raise ArgumentError, "n must be a positive integer"
  end