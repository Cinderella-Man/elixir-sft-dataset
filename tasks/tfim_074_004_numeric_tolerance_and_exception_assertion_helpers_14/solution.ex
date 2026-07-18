    test "fails when no exception is raised" do
      result =
        try do
          assert_raises_message(RuntimeError, "boom", fn -> :ok end)
          :no_failure
        rescue
          e in ExUnit.AssertionError -> e.message
        end

      refute result == :no_failure
      assert result =~ "no exception"
    end