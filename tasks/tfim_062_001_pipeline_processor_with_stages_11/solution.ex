  test "stages after a failing one are never called" do
    called = Agent.start_link(fn -> false end) |> elem(1)

    pipeline =
      Pipeline.new()
      |> Pipeline.stage(:fail, fail_stage(:boom))
      |> Pipeline.stage(:should_not_run, fn v ->
        Agent.update(called, fn _ -> true end)
        {:ok, v}
      end)

    Pipeline.run(pipeline, nil)
    refute Agent.get(called, & &1)
  end