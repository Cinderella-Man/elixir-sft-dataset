defp full?(:infinity, _len), do: false
defp full?(cap, len) when is_integer(cap), do: len >= cap