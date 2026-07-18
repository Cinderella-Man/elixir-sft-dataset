  test "a compensation that is not arity-1 raises ArgumentError" do
    assert_raise ArgumentError, fn ->
      ParallelSaga.stage(ParallelSaga.new(), [{:a, fn _ -> :ok end, fn -> :ok end}])
    end
  end