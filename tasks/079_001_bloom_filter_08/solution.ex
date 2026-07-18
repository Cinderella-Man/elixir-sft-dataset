  # Each "word" in the `bits` tuple holds 64 bits.
  defp word_index(bit_index), do: div(bit_index, 64)