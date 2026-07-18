  @spec split_line(binary()) :: {binary(), binary()}
  defp split_line(binary) do
    [line, rest] = :binary.split(binary, "\n")
    {line, rest}
  end