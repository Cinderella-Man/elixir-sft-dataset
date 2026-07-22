  @spec next_message(term(), non_neg_integer()) :: :ok
  def next_message(expected, timeout_ms \\ 1_000) do
    receive do
      msg ->
        if msg == expected do
          :ok
        else
          ExUnit.Assertions.flunk("""
          assert_next_message failed

            expected message: #{inspect(expected)}
            received message: #{inspect(msg)}
          """)
        end
    after
      timeout_ms ->
        ExUnit.Assertions.flunk("""
        assert_next_message timed out

          expected message: #{inspect(expected)}
          waited          : #{timeout_ms}ms
          no message arrived in the mailbox within the timeout
        """)
    end
  end