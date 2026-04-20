defp parse_range_or_value(str, lo, hi) do
  case String.split(str, "-") do
    [single] ->
      case parse_int(single) do
        {:ok, v} when v >= lo and v <= hi -> {:ok, MapSet.new([v])}
        _ -> :error
      end

    [from_str, to_str] ->
      with {:ok, from} <- parse_int(from_str),
            {:ok, to} <- parse_int(to_str),
            true <- from >= lo && to <= hi && from <= to || :error do
        {:ok, MapSet.new(from..to)}
      else
        _ -> :error
      end

    _ ->
      :error
  end
end
