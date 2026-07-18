  test "an early step's compensation sees results stored by later completed steps" do
    seen = fn name ->
      fn ctx ->
        Recorder.record({:comp_saw, name, Map.take(ctx, [:a, :b, :c, :start])})
        {:ok, :undone}
      end
    end

    saga =
      RetrySaga.new()
      |> RetrySaga.step(:a, flaky_action(:a, 0, 1), seen.(:a))
      |> RetrySaga.step(:b, flaky_action(:b, 0, 2), seen.(:b))
      |> RetrySaga.step(:c, always_fail(:c, :boom), comp(:c))

    assert {:error, _err} = RetrySaga.execute(saga, %{start: :ctx})

    assert {:comp_saw, :a, %{a: 1, b: 2, start: :ctx}} in Recorder.events()
    assert {:comp_saw, :b, %{a: 1, b: 2, start: :ctx}} in Recorder.events()
  end