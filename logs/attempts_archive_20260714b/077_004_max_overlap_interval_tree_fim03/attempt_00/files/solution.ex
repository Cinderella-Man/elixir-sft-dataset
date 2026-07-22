  defp prefix_sum(nil, _point), do: 0

  defp prefix_sum(%{coord: c, delta: d, left: left, right: right}, point) do
    if c <= point do
      sum_of(left) + d + prefix_sum(right, point)
    else
      prefix_sum(left, point)
    end
  end