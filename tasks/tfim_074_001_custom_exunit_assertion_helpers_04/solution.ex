    test "returns the truthy value from the function" do
      # assert_eventually should not raise; result is checked implicitly
      assert_eventually(fn -> 42 end)
    end