    test "failure message includes total time waited" do
      message =
        try do
          assert_eventually(fn -> nil end, 150, 40)
          ""
        rescue
          e in ExUnit.AssertionError -> e.message
        end

      assert message =~ "150" or message =~ "ms"
    end