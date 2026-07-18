  test "execute with two arguments uses default options", %{rw: rw} do
    assert {:ok, :arity_two} = RetryWorker.execute(rw, fn -> {:ok, :arity_two} end)
  end