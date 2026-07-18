  @doc "Returns `true` if all `k` slots for `item` read as `1`."
  @spec member?(t(), term()) :: boolean()
  def member?(%__MODULE__{m: m, k: k, ref: ref}, item) do
    Enum.all?(0..(k - 1), fn seed ->
      :atomics.get(ref, hash(item, seed, m) + 1) == 1
    end)
  end