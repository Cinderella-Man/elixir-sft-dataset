    test "passes for an empty list" do
      assert_sorted_by([], & &1)
    end