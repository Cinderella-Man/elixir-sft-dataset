  # Derive k independent hash values from a single hash primitive by hashing
  # the tuple {seed, item}.  :erlang.phash2/2 accepts any Erlang term and
  # returns a non-negative integer in 0..range-1.
  defp hash(item, seed, m) do
    :erlang.phash2({seed, item}, m)
  end