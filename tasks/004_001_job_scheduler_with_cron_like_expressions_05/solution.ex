# Parse a single cron field token into a sorted MapSet of integers.
defp parse_field(token, lo, hi) do
  token
  |> String.split(",")
  |> Enum.reduce_while(MapSet.new(), fn part, acc ->
    case parse_part(part, lo, hi) do
      {:ok, values} -> {:cont, MapSet.union(acc, values)}
      :error -> {:halt, :error}
    end
  end)
  |> case do
    :error -> :error
    set -> {:ok, set}
  end
end
