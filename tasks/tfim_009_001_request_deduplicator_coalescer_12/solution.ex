  test "sequential calls on the same key each trigger their own execution", %{dd: dd} do
    {:ok, counter} = Agent.start_link(fn -> 0 end)

    for _ <- 1..5 do
      Dedup.execute(dd, "seq", fn ->
        Agent.update(counter, &(&1 + 1))
        {:ok, :done}
      end)
    end

    # Each sequential call should have executed the function
    assert Agent.get(counter, & &1) == 5
  end