  # Insert into an empty tree — create a leaf node.
  @spec do_insert(t(), interval()) :: node_t()
  defp do_insert(nil, interval), do: make_node(interval, nil, nil)

  # Insert into an existing node: descend by start value, rebuild upward,
  # then rebalance.  Duplicates are stored (multiple identical intervals allowed).
  defp do_insert(%{interval: {ns, _nf}} = node, {s, _f} = interval) do
    updated =
      if s <= ns do
        make_node(node.interval, do_insert(node.left, interval), node.right)
      else
        make_node(node.interval, node.left, do_insert(node.right, interval))
      end

    rebalance(updated)
  end