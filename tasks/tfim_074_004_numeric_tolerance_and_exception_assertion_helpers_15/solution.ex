    test "fails when a different exception type is raised" do
      result =
        try do
          assert_raises_message(ArgumentError, "boom", fn -> raise RuntimeError, "boom" end)
          :no_failure
        rescue
          e in ExUnit.AssertionError -> e.message
        end

      refute result == :no_failure
      assert result =~ "RuntimeError"
    end