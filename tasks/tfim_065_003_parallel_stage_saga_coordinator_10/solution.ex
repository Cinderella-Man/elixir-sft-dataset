  test "bad step tuple raises ArgumentError" do
    assert_raise ArgumentError, fn ->
      ParallelSaga.stage(ParallelSaga.new(), [{:a, fn -> :ok end, fn _ -> :ok end}])
    end
  end