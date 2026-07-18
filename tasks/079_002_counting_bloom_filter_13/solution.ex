  @doc """
  Adds `item` (multiset insert) and returns the updated filter.
  """
  @spec add(t(), term()) :: t()
  def add(%__MODULE__{m: m, k: k, counters: counters, size: size} = filter, item) do
    new_counters =
      Enum.reduce(0..(k - 1), counters, fn seed, acc ->
        increment(acc, hash(item, seed, m))
      end)

    %{filter | counters: new_counters, size: size + 1}
  end