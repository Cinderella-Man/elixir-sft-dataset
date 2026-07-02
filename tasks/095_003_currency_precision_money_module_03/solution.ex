  def to_string(%__MODULE__{amount: amount, currency: currency}) do
    exp = exponent(currency)
    sign = if amount < 0, do: "-", else: ""
    abs_amount = abs(amount)

    if exp == 0 do
      "#{sign}#{abs_amount} #{currency}"
    else
      divisor = Integer.pow(10, exp)
      major = div(abs_amount, divisor)
      minor = rem(abs_amount, divisor)
      minor_str = minor |> Integer.to_string() |> String.pad_leading(exp, "0")
      "#{sign}#{major}.#{minor_str} #{currency}"
    end
  end