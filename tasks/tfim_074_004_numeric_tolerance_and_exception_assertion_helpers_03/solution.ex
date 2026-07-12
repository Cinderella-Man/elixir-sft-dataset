    test "passes for a strictly decreasing sequence" do
      assert_monotonic([10, 5, 1, -3], :decreasing)
    end