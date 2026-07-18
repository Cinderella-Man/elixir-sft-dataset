  defp do_insert(nil, interval), do: make_node(interval, nil, nil)

  defp do_insert(%{interval: ni, left: l, right: r}, interval) do
    if interval <= ni do
      balance(ni, do_insert(l, interval), r)
    else
      balance(ni, l, do_insert(r, interval))
    end
  end