  # Right-heavy: left rotation around `x`, promoting right child `y`.
  #
  #     x                  y
  #    / \                / \
  #   A   y      =>      x   C
  #      / \            / \
  #     B   C          A   B
  #
  defp rotate_left(%{
         interval: xi,
         left: a,
         right: %{interval: yi, left: b, right: c}
       }) do
    make_node(yi, make_node(xi, a, b), c)
  end