  defp rotate_left(interval, left, %{left: rl, right: rr} = right) do
    if size(rl) < @ratio * size(rr) do
      single_left(interval, left, right)
    else
      double_left(interval, left, right)
    end
  end