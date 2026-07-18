  test "stages after a failing sequential stage never run" do
    {:ok, ran?} = Agent.start_link(fn -> false end)

    pipeline =
      Pipeline.new()
      |> Pipeline.stage(:boom, fn _ -> {:error, :nope} end)
      |> Pipeline.stage(:later, fn v ->
        Agent.update(ran?, fn _ -> true end)
        {:ok, v}
      end)

    assert {:error, :boom, :nope} = Pipeline.run(pipeline, 1)
    refute Agent.get(ran?, & &1)
  end