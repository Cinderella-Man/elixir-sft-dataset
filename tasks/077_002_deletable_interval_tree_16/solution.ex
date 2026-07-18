  defp rotate_right(interval, %{left: ll, right: lr} = left, right) do
    if size(lr) < @ratio * size(ll) do
      single_right(interval, left, right)
    else
      double_right(interval, left, right)
    end
  end