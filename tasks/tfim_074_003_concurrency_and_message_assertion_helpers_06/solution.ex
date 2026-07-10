  test "assert_no_message watches the mailbox for at least the documented default of 100ms" do
    min_elapsed_us =
      1..5
      |> Enum.map(fn _ ->
        started = System.monotonic_time(:microsecond)
        assert_no_message()
        System.monotonic_time(:microsecond) - started
      end)
      |> Enum.min()

    assert min_elapsed_us >= 100_000
  end