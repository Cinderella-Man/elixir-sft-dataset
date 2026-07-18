  defp get_bit(bits, bit_index) do
    wi = div(bit_index, 64)
    bo = rem(bit_index, 64)
    Bitwise.band(Bitwise.bsr(elem(bits, wi), bo), 1)
  end