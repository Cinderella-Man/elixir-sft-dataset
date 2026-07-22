    cond do
      is_nil(tree) ->
        # Empty subtree: nothing to add.
        acc

      tree.max_finish < point ->
        # Prune rule 1: no interval in this subtree reaches far enough
        # right to contain the point.
        acc

      true ->
        {s, f} = tree.interval

        # Add the node's own interval iff it encloses the point.
        acc =
          if s <= point and point <= f do
            [tree.interval | acc]
          else
            acc
          end

        # Always recurse left (guarded by max_finish above).
        acc = do_enclosing(tree.left, point, acc)

        # Prune rule 2: right subtree starts are all >= s; skip if s > point.
        if s <= point do
          do_enclosing(tree.right, point, acc)
        else
          acc
        end
    end