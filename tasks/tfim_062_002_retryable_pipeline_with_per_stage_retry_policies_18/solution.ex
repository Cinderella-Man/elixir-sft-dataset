  test "a later stage failing reports its own name and only its own attempt count" do
    {:ok, firsts} = Agent.start_link(fn -> 0 end)

    first = fn v ->
      Agent.update(firsts, &(&1 + 1))
      {:ok, v}
    end

    pipeline =
      Pipeline.new()
      |> Pipeline.stage(:first, first, retries: 4)
      |> Pipeline.stage(:second, always_fail(:down), retries: 1)

    assert {:error, :second, :down, 2} = Pipeline.run(pipeline, :in)
    assert Agent.get(firsts, & &1) == 1
  end