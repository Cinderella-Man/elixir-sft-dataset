  test "stages receive exactly the previous stage's output" do
    acc = Agent.start_link(fn -> [] end) |> elem(1)

    pipeline =
      Pipeline.new()
      |> Pipeline.stage(:one, fn v ->
        Agent.update(acc, &[v | &1])
        {:ok, v + 10}
      end)
      |> Pipeline.stage(:two, fn v ->
        Agent.update(acc, &[v | &1])
        {:ok, v + 10}
      end)
      |> Pipeline.stage(:three, fn v ->
        Agent.update(acc, &[v | &1])
        {:ok, v + 10}
      end)

    assert {:ok, 30, _} = Pipeline.run(pipeline, 0)
    assert Enum.reverse(Agent.get(acc, & &1)) == [0, 10, 20]
  end