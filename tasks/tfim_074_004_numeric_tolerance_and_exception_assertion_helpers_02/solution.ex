    test "passes for a strictly increasing sequence" do
      assert_monotonic([1, 2, 3, 10])
    end