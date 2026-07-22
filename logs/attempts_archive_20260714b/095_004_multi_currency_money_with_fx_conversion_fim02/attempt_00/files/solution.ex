  def convert(%__MODULE__{amount: amount, currency: from}, to, rates)
      when is_atom(to) and is_map(rates) do
    rate_from = fetch_rate(rates, from)
    rate_to = fetch_rate(rates, to)
    %__MODULE__{amount: round(amount * rate_from / rate_to), currency: to}
  end