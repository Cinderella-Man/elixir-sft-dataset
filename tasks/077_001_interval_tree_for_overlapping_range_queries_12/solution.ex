  # Left subtree is two levels taller: single right rotation when the left child
  # leans left (Left-Left), double rotation when it leans right (Left-Right).
  @spec fix_left_heavy(node_t()) :: node_t()
  defp fix_left_heavy(%{interval: xi, left: %{left: ll, right: lr} = l, right: r} = node) do
    case height(ll) - height(lr) do
      1 -> rotate_right(node)
      -1 -> rotate_right(make_node(xi, rotate_left(l), r))
    end
  end