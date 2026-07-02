  @spec resolve(MapSet.t(category())) :: atom()
  defp resolve(set) do
    case MapSet.to_list(set) do
      [] -> :string
      [category] -> category
      many -> if Enum.all?(many, &(&1 in [:integer, :float])), do: :float, else: :string
    end
  end