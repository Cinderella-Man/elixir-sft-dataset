  defp ceil_positive(x) when is_number(x) do
    c = trunc(x)
    c = if c < x, do: c + 1, else: c
    max(c, 1)
  end