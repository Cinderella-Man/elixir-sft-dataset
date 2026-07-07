  defp slice_member?(%{m: m, k: k, bits: bits}, item) do
    Enum.all?(0..(k - 1), fn seed ->
      get_bit(bits, hash(item, seed, m)) == 1
    end)
  end