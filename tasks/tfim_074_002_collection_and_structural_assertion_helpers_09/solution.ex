    test "passes with duplicate elements in the subset" do
      assert_subset([1, 1, 2], [1, 2, 3])
    end