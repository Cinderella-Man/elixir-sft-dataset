  @spec make_node(integer(), integer(), t(), t()) :: node_t()
  defp make_node(coord, delta, left, right) do
    lsum = sum_of(left)
    after_node = lsum + delta

    node_sum = lsum + delta + sum_of(right)
    node_best = max(best_of(left), max(after_node, after_node + best_of(right)))
    node_height = 1 + max(height(left), height(right))

    %{
      coord: coord,
      delta: delta,
      sum: node_sum,
      best: node_best,
      height: node_height,
      left: left,
      right: right
    }
  end