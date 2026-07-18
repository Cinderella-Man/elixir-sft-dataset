  test "uses default options when not specified", %{rw: rw} do
    func = fn -> {:ok, :defaults_work} end
    assert {:ok, :defaults_work} = ClassifiedRetryWorker.execute(rw, func, [])
  end