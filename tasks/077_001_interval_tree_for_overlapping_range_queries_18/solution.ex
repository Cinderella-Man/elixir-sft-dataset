  # Left-heavy: right rotation around `x`, promoting left child `y`.
  #
  #       x                y
  #      / \              / \
  #     y   C    =>      A   x
  #    / \                  / \
  #   A   B                B   C
  #
  defp rotate_right(%{
         interval: xi,
         left: %{interval: yi, left: a, right: b},
         right: c
       }) do
    make_node(yi, a, make_node(xi, b, c))
  end