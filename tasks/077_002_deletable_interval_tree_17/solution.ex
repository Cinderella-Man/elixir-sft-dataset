  defp single_left(i1, t1, %{interval: i2, left: t2, right: t3}) do
    make_node(i2, make_node(i1, t1, t2), t3)
  end