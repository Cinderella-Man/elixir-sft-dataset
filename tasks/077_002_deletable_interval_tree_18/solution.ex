  defp single_right(i1, %{interval: i2, left: t1, right: t2}, t3) do
    make_node(i2, t1, make_node(i1, t2, t3))
  end