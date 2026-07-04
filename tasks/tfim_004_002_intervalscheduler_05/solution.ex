  test "unregister returns :ok when found, :not_found otherwise", %{is: is} do
    assert {:error, :not_found} = IntervalScheduler.unregister(is, "ghost")

    :ok =
      IntervalScheduler.register(is, "j", {:every, 1, :seconds}, {JobSink, :ping, [self(), :x]})

    assert :ok = IntervalScheduler.unregister(is, "j")
    assert {:error, :not_found} = IntervalScheduler.next_run(is, "j")
  end