  @spec numeric_only?([atom()]) :: boolean()
  defp numeric_only?(categories) do
    Enum.all?(categories, &(&1 in [:integer, :float]))
  end