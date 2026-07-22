  defp make_slice(index, capacity0, p0) do
    p_i = p0 * :math.pow(@ratio, index)
    capacity = max(1, round(capacity0 * :math.pow(@growth, index)))
    m = max(1, ceil(-capacity * :math.log(p_i) / (@ln2 * @ln2)))
    k = max(1, round(m / capacity * @ln2))
    num_words = ceil(m / 64)

    %{m: m, k: k, bits: Tuple.duplicate(0, num_words), capacity: capacity, count: 0}
  end