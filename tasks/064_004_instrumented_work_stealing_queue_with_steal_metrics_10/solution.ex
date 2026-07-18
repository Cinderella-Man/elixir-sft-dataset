  defp batch_size(:half, len), do: max(div(len, 2), 1)
  defp batch_size(n, _len) when is_integer(n) and n > 0, do: n