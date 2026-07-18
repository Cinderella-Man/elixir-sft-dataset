  test "rebalancing never disturbs earlier persistent versions" do
    # Version k holds the nested intervals [1,1000]..[k,1000], so its depth at
    # point k is exactly k and the leftmost maximum sits at k.
    versions = Enum.scan(1..64, T.new(), fn i, acc -> T.insert(acc, {i, 1000}) end)

    for {tree, k} <- Enum.with_index(versions, 1) do
      assert T.max_overlap(tree) == k
      assert T.busiest_point(tree) == k
      assert T.depth_at(tree, k) == k
      assert T.depth_at(tree, 1000) == k
      assert T.depth_at(tree, 1001) == 0
    end
  end