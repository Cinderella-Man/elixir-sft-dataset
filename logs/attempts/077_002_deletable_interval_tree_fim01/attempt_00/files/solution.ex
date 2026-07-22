  defp balance(interval, left, right) do
    ls = size(left)
    rs = size(right)

    cond do
      ls + rs <= 1 -> make_node(interval, left, right)
      rs > @delta * ls -> rotate_left(interval, left, right)
      ls > @delta * rs -> rotate_right(interval, left, right)
      true -> make_node(interval, left, right)
    end
  end