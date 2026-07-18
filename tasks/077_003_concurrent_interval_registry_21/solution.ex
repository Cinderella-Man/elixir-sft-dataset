  defp t_rotate_left(%{right: %{} = y} = x) do
    t_node(y.s, y.f, y.id, t_node(x.s, x.f, x.id, x.left, y.left), y.right)
  end