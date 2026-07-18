  test "max_attempts of one performs a single attempt and never retries" do
    Process.put(:once, 0)

    result =
      Saga.new()
      |> Saga.retriable(
        :commit,
        fn _ ->
          Process.put(:once, Process.get(:once) + 1)
          {:error, :nope}
        end,
        1
      )
      |> Saga.execute(%{})

    assert {:error, :commit, {:retries_exhausted, :nope}, []} = result
    assert Process.get(:once) == 1
  end