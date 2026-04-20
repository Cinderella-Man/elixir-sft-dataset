defp parse_interval({:every, n, :seconds}) when is_integer(n) and n > 0, do: {:ok, n}
defp parse_interval({:every, n, :minutes}) when is_integer(n) and n > 0, do: {:ok, n * 60}
defp parse_interval({:every, n, :hours}) when is_integer(n) and n > 0, do: {:ok, n * 3_600}
defp parse_interval({:every, n, :days}) when is_integer(n) and n > 0, do: {:ok, n * 86_400}
defp parse_interval(_), do: :error
