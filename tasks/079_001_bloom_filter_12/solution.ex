  @doc """
  Creates a new, empty Bloom filter.

  ## Parameters

    - `expected_size`      – anticipated number of items to be inserted (`n`).
    - `false_positive_rate` – desired false-positive probability, e.g. `0.01`
                              for 1%.  Must be in the range `(0.0, 1.0)`.

  ## Examples

      iex> BloomFilter.new(1_000, 0.01)
      %BloomFilter{m: 9586, k: 7, bits: ...}

  """
  @spec new(pos_integer(), float()) :: t()
  def new(expected_size, false_positive_rate)
      when is_integer(expected_size) and expected_size > 0 and
             is_float(false_positive_rate) and false_positive_rate > 0.0 and
             false_positive_rate < 1.0 do
    m = optimal_m(expected_size, false_positive_rate)
    k = optimal_k(m, expected_size)

    # Represent bits as a tuple of integers where each integer is used as a
    # 64-bit word.  This gives O(1) element access via `elem/2`.
    num_words = ceil(m / 64)
    bits = Tuple.duplicate(0, num_words)

    %__MODULE__{m: m, k: k, bits: bits}
  end