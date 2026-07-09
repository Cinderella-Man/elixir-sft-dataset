  test "invalid max_attempts raises ArgumentError" do
    assert_raise ArgumentError, fn ->
      RetrySaga.step(RetrySaga.new(), :a, fn _ -> {:ok, 1} end, fn _ -> :ok end, max_attempts: 0)
    end
  end