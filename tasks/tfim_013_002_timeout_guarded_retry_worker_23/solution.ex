  test "execute called with only server and func uses the default option set", %{rw: rw} do
    assert {:ok, :two_arg} = TimeoutRetryWorker.execute(rw, fn -> {:ok, :two_arg} end)
  end