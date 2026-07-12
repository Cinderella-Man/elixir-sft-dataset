    test "passes for equal keys (non-strict ascending)" do
      assert_sorted_by([%{age: 10}, %{age: 10}], & &1.age)
    end