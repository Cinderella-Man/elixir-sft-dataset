  # Non-short-circuiting comparison: every byte pair is always examined and the
  # per-byte differences are accumulated, so timing does not leak where two MACs
  # first differ. Binaries of differing size are rejected outright.
  @spec constant_time_equal?(binary(), binary()) :: boolean()
  defp constant_time_equal?(left, right)
       when is_binary(left) and is_binary(right) and byte_size(left) == byte_size(right) do
    diff =
      left
      |> :binary.bin_to_list()
      |> Enum.zip(:binary.bin_to_list(right))
      |> Enum.reduce(0, fn {a, b}, acc -> acc + abs(a - b) end)

    diff === 0
  end

  defp constant_time_equal?(_left, _right), do: false