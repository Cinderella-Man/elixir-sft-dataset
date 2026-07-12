    test "failure message includes the computed keys" do
      message =
        try do
          assert_sorted_by([%{age: 40}, %{age: 10}], & &1.age)
          ""
        rescue
          e in ExUnit.AssertionError -> e.message
        end

      assert message =~ "key"
    end