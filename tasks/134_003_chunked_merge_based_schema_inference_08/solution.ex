  @spec split_records([row()], boolean()) :: {[String.t()] | nil, [row()]}
  defp split_records([], true), do: {nil, []}

  defp split_records([header | rest], true) do
    {Enum.map(header, fn {value, _quoted?} -> value end), rest}
  end

  defp split_records(records, false), do: {nil, records}