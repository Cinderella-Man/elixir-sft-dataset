  @spec rebalance(node_t()) :: node_t()
  defp rebalance(%{coord: xc, delta: xd, left: l, right: r} = node) do
    lh = height(l)
    rh = height(r)

    cond do
      lh - rh > 1 ->
        if balance_factor(l) >= 0 do
          rotate_right(node)
        else
          rotate_right(make_node(xc, xd, rotate_left(l), r))
        end

      rh - lh > 1 ->
        if balance_factor(r) <= 0 do
          rotate_left(node)
        else
          rotate_left(make_node(xc, xd, l, rotate_right(r)))
        end

      true ->
        node
    end
  end