  test "random interval sets match a brute-force reference in shuffled orders" do
    :rand.seed(:exsss, {7, 11, 13})

    for _round <- 1..30 do
      intervals =
        for _ <- 1..25 do
          s = :rand.uniform(21) - 11
          {s, s + :rand.uniform(6) - 1}
        end

      tree =
        intervals
        |> Enum.shuffle()
        |> Enum.reduce(T.new(), &T.insert(&2, &1))

      {expected_max, expected_bp} = brute_stats(intervals)

      assert T.max_overlap(tree) == expected_max
      assert T.busiest_point(tree) == expected_bp

      for p <- -13..20 do
        assert T.depth_at(tree, p) == brute_depth(intervals, p)
      end
    end
  end