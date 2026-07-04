  test "best-effort compensation: an erroring compensation does not stop the rest" do
    saga =
      ParallelSaga.new()
      |> ParallelSaga.stage([{:a, ok_action(:a, 1), comp(:a, {:ok, :undo_a})}])
      |> ParallelSaga.stage([
        {:b, ok_action(:b, 2), comp(:b, {:error, :undo_failed})},
        {:c, fail_action(:c, :nope), comp(:c)}
      ])

    assert {:error, err} = ParallelSaga.execute(saga, %{})
    assert err.compensated == [:b, :a]
    assert err.compensations == %{b: {:error, :undo_failed}, a: {:ok, :undo_a}}
  end