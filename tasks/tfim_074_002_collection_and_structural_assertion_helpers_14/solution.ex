    test "accepts a single key (not wrapped in a list)" do
      assert_has_keys(%{a: 1}, :a)
    end