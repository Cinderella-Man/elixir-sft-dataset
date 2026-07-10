  test "assert_no_message reports the default 100ms window when it catches a message" do
    send(self(), :unexpected)

    error =
      assert_raise ExUnit.AssertionError, fn ->
        assert_no_message()
      end

    assert error.message =~ "100"
    assert error.message =~ ":unexpected"
  end