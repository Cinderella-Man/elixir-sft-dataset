  defp double_left(i1, t1, right) do
    %{interval: i2, left: %{interval: i3, left: t2, right: t3}, right: t4} = right
    make_node(i3, make_node(i1, t1, t2), make_node(i2, t3, t4))
  end