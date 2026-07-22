  def no_message(within_ms \\ 100) do
    receive do
      msg ->
        ExUnit.Assertions.flunk("""
        assert_no_message failed

          expected no message within #{within_ms}ms
          but received: #{inspect(msg)}
        """)
    after
      within_ms -> :ok
    end
  end