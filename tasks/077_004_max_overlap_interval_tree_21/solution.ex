  defp rotate_left(%{
         coord: xc,
         delta: xd,
         left: a,
         right: %{coord: yc, delta: yd, left: b, right: c}
       }) do
    make_node(yc, yd, make_node(xc, xd, a, b), c)
  end