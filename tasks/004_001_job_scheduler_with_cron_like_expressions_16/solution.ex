  defp parse_cron(expression) when is_binary(expression) do
    parts = String.split(expression)

    if length(parts) != 5 do
      :error
    else
      fields = Enum.zip(@field_order, parts)

      result =
        Enum.reduce_while(fields, %{}, fn {field, token}, acc ->
          {lo, hi} = Map.fetch!(@field_ranges, field)

          case parse_field(token, lo, hi) do
            {:ok, values} -> {:cont, Map.put(acc, field, values)}
            :error -> {:halt, :error}
          end
        end)

      case result do
        :error -> :error
        map -> {:ok, map}
      end
    end
  end