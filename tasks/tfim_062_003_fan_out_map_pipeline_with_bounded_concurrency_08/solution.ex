  test "stages after a failing map stage never run" do
    {:ok, ran?} = Agent.start_link(fn -> false end)

    pipeline =
      Pipeline.new()
      |> Pipeline.map_stage(:m, fn _ -> {:error, :bad} end)
      |> Pipeline.stage(:next, fn v ->
        Agent.update(ran?, fn _ -> true end)
        {:ok, v}
      end)

    assert {:error, :m, :bad} = Pipeline.run(pipeline, [1, 2])
    refute Agent.get(ran?, & &1)
  end