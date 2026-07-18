  defp make_node({_s, f} = interval, left, right) do
    n = 1 + size(left) + size(right)
    mf = f |> max_with_child(left) |> max_with_child(right)
    %{interval: interval, max_finish: mf, size: n, left: left, right: right}
  end