    test "passes immediately when the function is already truthy" do
      assert_eventually(fn -> true end)
    end