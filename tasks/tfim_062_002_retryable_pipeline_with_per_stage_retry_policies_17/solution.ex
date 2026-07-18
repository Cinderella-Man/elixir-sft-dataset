  test "retries: 2 allows success on exactly the third and final permitted attempt" do
    {:ok, ag} = Agent.start_link(fn -> 0 end)

    flaky = fn v ->
      n = Agent.get_and_update(ag, fn c -> {c + 1, c + 1} end)
      if n < 3, do: {:error, :not_yet}, else: {:ok, v}
    end

    pipeline = Pipeline.new() |> Pipeline.stage(:edge, flaky, retries: 2)

    assert {:ok, :v, [%{stage: :edge, attempts: 3}]} = Pipeline.run(pipeline, :v)
  end