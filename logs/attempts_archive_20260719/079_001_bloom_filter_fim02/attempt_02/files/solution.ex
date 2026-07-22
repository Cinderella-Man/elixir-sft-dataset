  def merge(
        %__MODULE__{m: m, k: k, bits: bits1} = f1,
        %__MODULE__{m: m, k: k, bits: bits2}
      ) do
    merged_bits =
      bits1
      |> Tuple.to_list()
      |> Enum.zip(Tuple.to_list(bits2))
      |> Enum.map(fn {w1, w2} -> Bitwise.bor(w1, w2) end)
      |> List.to_tuple()

    %{f1 | bits: merged_bits}
  end

  def merge(%__MODULE__{m: m1, k: k1}, %__MODULE__{m: m2, k: k2}) do
    raise ArgumentError,
          "cannot merge Bloom filters with different parameters: " <>
            "filter1 has m=#{m1}, k=#{k1}; filter2 has m=#{m2}, k=#{k2}"
  end