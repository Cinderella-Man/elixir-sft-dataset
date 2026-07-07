  defp decrement(counters, idx) do
    case elem(counters, idx) do
      0 -> counters
      v when v >= @max_count -> counters
      v -> put_elem(counters, idx, v - 1)
    end
  end