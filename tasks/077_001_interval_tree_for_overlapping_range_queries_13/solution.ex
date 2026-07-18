  # Right subtree is two levels taller: single left rotation when the right child
  # leans right (Right-Right), double rotation when it leans left (Right-Left).
  @spec fix_right_heavy(node_t()) :: node_t()
  defp fix_right_heavy(%{interval: xi, left: l, right: %{left: rl, right: rr} = r} = node) do
    case height(rl) - height(rr) do
      -1 -> rotate_left(node)
      1 -> rotate_left(make_node(xi, l, rotate_right(r)))
    end
  end