  def total(list, currency, rates)
      when is_list(list) and is_atom(currency) and is_map(rates) do
    sum =
      Enum.reduce(list, 0, fn %__MODULE__{} = m, acc ->
        acc + convert(m, currency, rates).amount
      end)

    %__MODULE__{amount: sum, currency: currency}
  end