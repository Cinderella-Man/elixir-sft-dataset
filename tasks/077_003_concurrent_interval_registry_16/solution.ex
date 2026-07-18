  defp t_node(s, f, id, left, right) do
    h = 1 + max(t_height(left), t_height(right))
    mf = f |> t_max_child(left) |> t_max_child(right)
    %{s: s, f: f, id: id, max_finish: mf, height: h, left: left, right: right}
  end