  @spec rebalance(node_t()) :: node_t()
  defp rebalance(%{left: l, right: r} = node) do
    case height(l) - height(r) do
      2 -> fix_left_heavy(node)
      -2 -> fix_right_heavy(node)
      d when abs(d) <= 1 -> node
    end
  end