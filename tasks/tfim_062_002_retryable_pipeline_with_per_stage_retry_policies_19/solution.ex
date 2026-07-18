  test "two stages registered under the same name both run in insertion order" do
    {:ok, ag} = Agent.start_link(fn -> [] end)

    step = fn tag ->
      fn v ->
        Agent.update(ag, &(&1 ++ [tag]))
        {:ok, v <> tag}
      end
    end

    pipeline =
      Pipeline.new()
      |> Pipeline.stage(:same, step.("a"))
      |> Pipeline.stage(:same, step.("b"))

    assert {:ok, "xab", [%{stage: :same}, %{stage: :same}]} = Pipeline.run(pipeline, "x")
    assert Agent.get(ag, & &1) == ["a", "b"]
  end