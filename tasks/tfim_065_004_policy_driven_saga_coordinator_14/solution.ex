  test "an earlier step's compensation sees later steps' stored results" do
    capture = fn name ->
      fn ctx ->
        Recorder.record({:comp_ctx, name, ctx})
        {:ok, :undone}
      end
    end

    saga =
      PolicySaga.new()
      |> PolicySaga.step(:a, ok_action(:a, 1), capture.(:a))
      |> PolicySaga.step(:b, ok_action(:b, 2), capture.(:b))
      |> PolicySaga.step(:c, fail_action(:c, :boom), comp(:c))

    assert {:error, _} = PolicySaga.execute(saga, %{seed: :s})

    ctxs =
      for {:comp_ctx, name, ctx} <- Recorder.events(), into: %{}, do: {name, ctx}

    assert ctxs[:a] == %{seed: :s, a: 1, b: 2}
    assert ctxs[:b] == %{seed: :s, a: 1, b: 2}
  end