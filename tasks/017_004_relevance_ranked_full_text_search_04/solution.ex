defp format_price(cents) do
  dollars = div(cents, 100)
  remainder = String.pad_leading(Integer.to_string(rem(cents, 100)), 2, "0")
  "#{dollars}.#{remainder}"
end