  def add(%__MODULE__{m: m, k: k, bits: bits} = filter, item) do
    new_bits =
      Enum.reduce(0..(k - 1), bits, fn seed, acc ->
        bit_index = hash(item, seed, m)
        set_bit(acc, bit_index)
      end)

    %{filter | bits: new_bits}
  end