  test "stages after a permanently failing stage are never called" do
    {:ok, ran?} = Agent.start_link(fn -> false end)

    pipeline =
      Pipeline.new()
      |> Pipeline.stage(:fail, always_fail(:dead), retries: 1)
      |> Pipeline.stage(:next, fn v ->
        Agent.update(ran?, fn _ -> true end)
        {:ok, v}
      end)

    assert {:error, :fail, :dead, 2} = Pipeline.run(pipeline, 0)
    refute Agent.get(ran?, & &1)
  end