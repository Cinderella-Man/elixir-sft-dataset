  @spec valid_date?(integer(), integer(), integer()) :: boolean()
  defp valid_date?(year, month, day) do
    match?({:ok, _}, Date.new(year, month, day))
  end