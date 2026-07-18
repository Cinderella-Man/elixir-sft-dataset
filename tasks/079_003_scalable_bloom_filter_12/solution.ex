  @doc "Creates a scalable filter with a single empty slice."
  @spec new(pos_integer(), float()) :: t()
  def new(initial_capacity, false_positive_rate)
      when is_integer(initial_capacity) and initial_capacity > 0 and
             is_float(false_positive_rate) and false_positive_rate > 0.0 and
             false_positive_rate < 1.0 do
    p0 = false_positive_rate * (1 - @ratio)
    first = make_slice(0, initial_capacity, p0)

    %__MODULE__{
      capacity0: initial_capacity,
      p0: p0,
      slices: [first],
      count: 0,
      items: MapSet.new()
    }
  end