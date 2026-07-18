  test "every retry of a stage receives the identical original input" do
    {:ok, seen} = Agent.start_link(fn -> [] end)

    recorder = fn v ->
      n = Agent.get_and_update(seen, fn acc -> {length(acc) + 1, acc ++ [v]} end)
      if n < 4, do: {:error, :again}, else: {:ok, :done}
    end

    pipeline = Pipeline.new() |> Pipeline.stage(:rec, recorder, retries: 5)

    assert {:ok, :done, [%{stage: :rec, attempts: 4}]} =
             Pipeline.run(pipeline, {:payload, 99})

    assert Agent.get(seen, & &1) == List.duplicate({:payload, 99}, 4)
  end