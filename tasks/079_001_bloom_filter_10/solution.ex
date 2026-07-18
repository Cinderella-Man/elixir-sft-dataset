  defp set_bit(bits, bit_index) do
    wi = word_index(bit_index)
    bo = bit_offset(bit_index)
    word = elem(bits, wi)
    put_elem(bits, wi, Bitwise.bor(word, Bitwise.bsl(1, bo)))
  end