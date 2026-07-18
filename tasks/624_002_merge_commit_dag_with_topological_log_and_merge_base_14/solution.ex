  @spec parse_parents(binary(), [hash()]) :: {[hash()], binary()}
  defp parse_parents("parent " <> _ = binary, acc) do
    {"parent " <> parent, rest} = split_line(binary)
    parse_parents(rest, [parent | acc])
  end

  defp parse_parents(binary, acc), do: {Enum.reverse(acc), binary}