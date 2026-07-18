  test "halted run still reports timing metadata for the stages that actually executed" do
    executed = Agent.start_link(fn -> [] end) |> elem(1)

    pipeline =
      Pipeline.new()
      |> Pipeline.stage(:first, fn v ->
        Agent.update(executed, &[:first | &1])
        {:ok, v}
      end)
      |> Pipeline.stage(:boom, fn _ ->
        Agent.update(executed, &[:boom | &1])
        {:error, :nope}
      end)
      |> Pipeline.stage(:never, fn v ->
        Agent.update(executed, &[:never | &1])
        {:ok, v}
      end)

    # A halted run reports the failing stage and its reason; per the public
    # contract the error tuple carries no metadata list.
    assert {:error, :boom, :nope} = Pipeline.run(pipeline, 1)
    assert Enum.reverse(Agent.get(executed, & &1)) == [:first, :boom]

    # The same executed prefix, run to completion, reports timing for exactly
    # those stages and nothing more.
    prefix =
      Pipeline.new()
      |> Pipeline.stage(:first, fn v -> {:ok, v} end)
      |> Pipeline.stage(:boom, fn v -> {:ok, v} end)

    assert {:ok, 1, metadata} = Pipeline.run(prefix, 1)
    assert Enum.map(metadata, & &1.stage) == [:first, :boom]
    assert Enum.all?(metadata, &(is_integer(&1.duration_us) and &1.duration_us >= 0))
  end