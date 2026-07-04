  test "retriable action is invoked exactly max_attempts times on exhaustion" do
    Process.put(:calls, 0)

    Saga.new()
    |> Saga.retriable(
      :p,
      fn _ ->
        Process.put(:calls, Process.get(:calls) + 1)
        {:error, :nope}
      end,
      4
    )
    |> Saga.execute(%{})

    assert Process.get(:calls) == 4
  end