  @spec resolve([cell()]) :: atom()
  defp resolve(cells) do
    cells
    |> Enum.map(&categorize/1)
    |> Enum.reject(&(&1 == :null))
    |> Enum.uniq()
    |> Enum.reduce(:bottom, &join/2)
    |> case do
      :bottom -> :string
      type -> type
    end
  end