    test "failure message includes last returned value" do
      message =
        try do
          assert_eventually(fn -> :still_pending end, 100, 40)
          ""
        rescue
          e in ExUnit.AssertionError -> e.message
        end

      assert message =~ "still_pending"
    end