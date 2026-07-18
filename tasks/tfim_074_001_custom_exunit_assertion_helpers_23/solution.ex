    test "timeout defaults to 1000ms and interval to 50ms, both reported" do
      message =
        try do
          assert_eventually(fn -> false end)
          ""
        rescue
          e in ExUnit.AssertionError -> e.message
        end

      assert message =~ ~r/timeout\D*1000ms/
      assert message =~ ~r/interval\D*50ms/
    end