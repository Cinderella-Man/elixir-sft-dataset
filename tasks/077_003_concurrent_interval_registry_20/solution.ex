  defp t_rotate_right(%{left: %{} = y} = x) do
    t_node(y.s, y.f, y.id, y.left, t_node(x.s, x.f, x.id, y.right, x.right))
  end