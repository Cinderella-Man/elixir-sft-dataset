  @spec resolve([atom()]) :: atom()
  defp resolve(categories) do
    case categories do
      [] -> :string
      [category] -> category
      many -> if Enum.all?(many, &(&1 in [:integer, :float])), do: :float, else: :string
    end
  end