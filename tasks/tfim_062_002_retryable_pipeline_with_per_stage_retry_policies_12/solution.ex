  test "only the failing stage is retried; earlier stages run once" do
    {:ok, ag} = Agent.start_link(fn -> 0 end)

    first = fn v -> {:ok, v + 1} end

    flaky = fn v ->
      n = Agent.get_and_update(ag, fn c -> {c + 1, c + 1} end)
      if n < 2, do: {:error, :x}, else: {:ok, v}
    end

    pipeline =
      Pipeline.new()
      |> Pipeline.stage(:first, first)
      |> Pipeline.stage(:flaky, flaky, retries: 3)

    assert {:ok, 6, [%{stage: :first, attempts: 1}, %{stage: :flaky, attempts: 2}]} =
             Pipeline.run(pipeline, 5)
  end