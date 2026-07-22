  def merge(
        %__MODULE__{m: m1, k: k1, bits: bits1} = f1,
        %__MODULE__{m: m2, k: k2, bits: bits2}
      )
      when m1 == m2 and k1 == k2 do
    merged_bits =
      Tuple.to_list(bits1)
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