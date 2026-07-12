    test "passes for a single-element list" do
      assert_sorted_by([%{age: 5}], & &1.age)
    end