  test "a halted item never invokes any later stage function" do
    parent = self()

    later = fn v ->
      send(parent, {:later_ran, v})
      {:ok, v}
    end

    pipeline =
      Pipeline.new()
      |> Pipeline.stage(:guard, fn v -> if v == :bomb, do: {:error, :boom}, else: {:ok, v} end)
      |> Pipeline.stage(:later, later)

    assert {:ok, report} = Pipeline.run(pipeline, [:bomb])

    assert report.failures == [%{index: 0, stage: :guard, reason: :boom}]
    assert report.successes == []
    refute_receive {:later_ran, _}, 50
  end