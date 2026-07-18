  @doc """
  Creates a new, empty counting Bloom filter sized for `expected_size` live
  items at the given `false_positive_rate`.
  """
  @spec new(pos_integer(), float()) :: t()
  def new(expected_size, false_positive_rate)
      when is_integer(expected_size) and expected_size > 0 and
             is_float(false_positive_rate) and false_positive_rate > 0.0 and
             false_positive_rate < 1.0 do
    m = optimal_m(expected_size, false_positive_rate)
    k = optimal_k(m, expected_size)
    %__MODULE__{m: m, k: k, counters: Tuple.duplicate(0, m), size: 0}
  end