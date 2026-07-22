  def merge(%__MODULE__{m: m, k: k} = f1, %__MODULE__{m: m, k: k} = f2) do
    merged =
      Tuple.to_list(f1.counters)
      |> Enum.zip(Tuple.to_list(f2.counters))
      |> Enum.map(fn {a, b} -> min(@max_count, a + b) end)
      |> List.to_tuple()

    %{f1 | counters: merged, size: f1.size + f2.size}
  end

  def merge(%__MODULE__{} = f1, %__MODULE__{} = f2) do
    raise ArgumentError,
          "cannot merge filters with different parameters: " <>
            "filter1 has m=#{f1.m}, k=#{f1.k}; filter2 has m=#{f2.m}, k=#{f2.k}"
  end