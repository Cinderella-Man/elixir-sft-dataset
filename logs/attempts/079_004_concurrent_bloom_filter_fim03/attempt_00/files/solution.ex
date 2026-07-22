  def add(%__MODULE__{m: m, k: k, ref: ref} = filter, item) do
    Enum.each(0..(k - 1), fn seed ->
      :atomics.put(ref, hash(item, seed, m) + 1, 1)
    end)

    filter
  end