  test "a stage that succeeds on a retry threads its result into the next stage" do
    {:ok, ag} = Agent.start_link(fn -> 0 end)

    flaky = fn v ->
      n = Agent.get_and_update(ag, fn c -> {c + 1, c + 1} end)
      if n < 2, do: {:error, :later}, else: {:ok, v * 3}
    end

    pipeline =
      Pipeline.new()
      |> Pipeline.stage(:flaky, flaky, retries: 2)
      |> Pipeline.stage(:after_flaky, ok_stage(&(&1 + 1)))

    assert {:ok, 22, [%{stage: :flaky, attempts: 2}, %{stage: :after_flaky, attempts: 1}]} =
             Pipeline.run(pipeline, 7)
  end