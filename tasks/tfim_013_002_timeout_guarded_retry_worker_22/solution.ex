  test "start_link with no arguments starts a usable worker" do
    assert {:ok, pid} = TimeoutRetryWorker.start_link()

    assert {:ok, :no_arg} =
             TimeoutRetryWorker.execute(pid, fn -> {:ok, :no_arg} end, max_retries: 0)
  end