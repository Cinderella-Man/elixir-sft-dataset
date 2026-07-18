  # Add `delta` to the accumulated value at `coord`, creating the node if absent.
  @spec bump(t(), integer(), integer()) :: node_t()
  defp bump(nil, coord, delta), do: make_node(coord, delta, nil, nil)

  defp bump(%{coord: c, delta: d, left: left, right: right}, coord, delta) do
    cond do
      coord < c ->
        rebalance(make_node(c, d, bump(left, coord, delta), right))

      coord > c ->
        rebalance(make_node(c, d, left, bump(right, coord, delta)))

      true ->
        # Same coordinate: accumulate the delta; structure/heights unchanged.
        make_node(c, d + delta, left, right)
    end
  end