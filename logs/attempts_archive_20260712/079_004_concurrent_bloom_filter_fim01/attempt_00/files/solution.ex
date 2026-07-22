  def new(expected_size, false_positive_rate)
      when is_integer(expected_size) and expected_size > 0 and
             is_float(false_positive_rate) and false_positive_rate > 0.0 and
             false_positive_rate < 1.0 do
    m = max(1, ceil(-expected_size * :math.log(false_positive_rate) / (@ln2 * @ln2)))
    k = max(1, round(m / expected_size * @ln2))
    ref = :atomics.new(m, signed: false)
    %__MODULE__{m: m, k: k, ref: ref}
  end