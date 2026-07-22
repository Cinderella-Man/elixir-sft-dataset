  # Rebalance a node whose subtree heights may differ by more than 1.
  @spec rebalance(node_t()) :: node_t()
  defp rebalance(%{interval: xi, left: l, right: r} = node) do
    lh = height(l)
    rh = height(r)

    cond do
      # Left-heavy by more than 1
      lh - rh > 1 ->
        if balance_factor(l) >= 0 do
          # Left-Left case: single right rotation
          rotate_right(node)
        else
          # Left-Right case: rotate left child left, then rotate node right
          rotate_right(make_node(xi, rotate_left(l), r))
        end

      # Right-heavy by more than 1
      rh - lh > 1 ->
        if balance_factor(r) <= 0 do
          # Right-Right case: single left rotation
          rotate_left(node)
        else
          # Right-Left case: rotate right child right, then rotate node left
          rotate_left(make_node(xi, l, rotate_right(r)))
        end

      # Already balanced
      true ->
        node
    end
  end