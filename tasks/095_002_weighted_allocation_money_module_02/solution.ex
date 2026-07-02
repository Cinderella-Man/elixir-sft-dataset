  @spec allocate(t(), [non_neg_integer()]) :: [t()]
  def allocate(%__MODULE__{amount: amount, currency: currency}, ratios)
      when is_list(ratios) and ratios != [] do
    unless Enum.all?(ratios, &(is_integer(&1) and &1 >= 0)) do
      raise ArgumentError, "ratios must be non-negative integers"
    end

    total = Enum.sum(ratios)

    if total <= 0 do
      raise ArgumentError, "ratios must sum to a strictly positive value"
    end

    shares = Enum.map(ratios, fn r -> div(amount * r, total) end)
    remainder = amount - Enum.sum(shares)
    unit = if remainder >= 0, do: 1, else: -1
    count = abs(remainder)

    shares
    |> Enum.with_index()
    |> Enum.map(fn {share, i} ->
      cents = if i < count, do: share + unit, else: share
      %__MODULE__{amount: cents, currency: currency}
    end)
  end

  def allocate(%__MODULE__{}, _ratios) do
    raise ArgumentError, "ratios must be a non-empty list of non-negative integers"
  end