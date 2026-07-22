  def merge(%__MODULE__{m: m, k: k, ref: into} = target, %__MODULE__{m: m, k: k, ref: from}) do
    Enum.each(1..m, fn idx ->
      if :atomics.get(from, idx) == 1 do
        :atomics.put(into, idx, 1)
      end
    end)

    target
  end

  def merge(%__MODULE__{} = f1, %__MODULE__{} = f2) do
    raise ArgumentError,
          "cannot merge filters with different parameters: " <>
            "filter1 has m=#{f1.m}, k=#{f1.k}; filter2 has m=#{f2.m}, k=#{f2.k}"
  end