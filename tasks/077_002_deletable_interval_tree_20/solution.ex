  defp double_right(i1, left, t4) do
    %{interval: i2, left: t1, right: %{interval: i3, left: t2, right: t3}} = left
    make_node(i3, make_node(i2, t1, t2), make_node(i1, t3, t4))
  end