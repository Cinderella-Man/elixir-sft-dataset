    test "passes when the map has all keys" do
      assert_has_keys(%{a: 1, b: 2, c: 3}, [:a, :b])
    end