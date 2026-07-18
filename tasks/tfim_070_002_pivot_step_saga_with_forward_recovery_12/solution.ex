  test "retries_exhausted carries the reason from the final attempt, not an earlier one" do
    Process.put(:n, 0)

    result =
      Saga.new()
      |> Saga.retriable(
        :commit,
        fn _ ->
          n = Process.get(:n) + 1
          Process.put(:n, n)
          {:error, {:attempt, n}}
        end,
        3
      )
      |> Saga.execute(%{})

    assert {:error, :commit, {:retries_exhausted, {:attempt, 3}}, []} = result
  end