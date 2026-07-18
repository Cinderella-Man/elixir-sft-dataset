  @spec constant_time_equal?(binary(), binary()) :: boolean()
  defp constant_time_equal?(left, right) when byte_size(left) == byte_size(right) do
    difference =
      left
      |> :binary.bin_to_list()
      |> Enum.zip(:binary.bin_to_list(right))
      |> Enum.reduce(0, fn {a, b}, acc -> :erlang.bor(acc, :erlang.bxor(a, b)) end)

    difference == 0
  end

  defp constant_time_equal?(_left, _right), do: false