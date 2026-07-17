  def split(%__MODULE__{amount: amount, currency: currency}, n)
      when is_integer(n) and n > 0 do
    base = div(amount, n)
    remainder = rem(amount, n)
    step = if remainder < 0, do: -1, else: 1
    extras = abs(remainder)

    Enum.map(0..(n - 1), fn i ->
      cents = if i < extras, do: base + step, else: base
      %__MODULE__{amount: cents, currency: currency}
    end)
  end