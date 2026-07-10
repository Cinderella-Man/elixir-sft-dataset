  test "next_message waits the documented default of 1000ms and reports it" do
    error =
      assert_raise ExUnit.AssertionError, fn ->
        AssertHelpers.next_message(:never_sent)
      end

    assert error.message =~ "timed out"
    assert error.message =~ "1000"
  end