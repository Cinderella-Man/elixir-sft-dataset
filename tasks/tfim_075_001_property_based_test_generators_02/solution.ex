    test "heavily weighted generator dominates output" do
      gen =
        Generators.one_of_weighted([
          {1, StreamData.constant(:rare)},
          {99, StreamData.constant(:common)}
        ])

      values = Enum.take(gen, 1_000)
      common_count = Enum.count(values, &(&1 == :common))

      # With 99:1 weighting, at least 90% should be :common
      assert common_count >= 900,
             "Expected >= 900 :common out of 1000, got #{common_count}"
    end