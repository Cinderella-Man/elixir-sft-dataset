  test "an earlier step's compensation sees later results but not the failing step's key" do
    record_ctx = fn name ->
      fn ctx ->
        Recorder.record({:comp_ctx, name, ctx})
        {:ok, :undone}
      end
    end

    saga =
      Saga.new()
      |> Saga.step(:a, ok_action(:a, 1), record_ctx.(:a))
      |> Saga.step(:b, ok_action(:b, 2), record_ctx.(:b))
      |> Saga.step(:c, fail_action(:c, :boom), comp(:c))

    assert {:error, _} = Saga.execute(saga, %{seed: :s})

    events = Recorder.events()
    assert {:comp_ctx, :a, ctx_a} = Enum.find(events, &match?({:comp_ctx, :a, _}, &1))

    assert ctx_a == %{seed: :s, a: 1, b: 2}
    refute Map.has_key?(ctx_a, :c)
  end