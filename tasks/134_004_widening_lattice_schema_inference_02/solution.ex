  @spec join(atom(), atom()) :: atom()
  defp join(:bottom, x), do: x
  defp join(x, :bottom), do: x
  defp join(x, x), do: x

  defp join(a, b) do
    pair = MapSet.new([a, b])

    cond do
      MapSet.subset?(pair, @numeric) -> :float
      MapSet.subset?(pair, @temporal) -> :datetime
      true -> :string
    end
  end