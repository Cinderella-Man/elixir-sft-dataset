  test "rejects duplicate names with :already_exists", %{is: is} do
    :ok =
      IntervalScheduler.register(is, "j", {:every, 1, :seconds}, {JobSink, :ping, [self(), :x]})

    assert {:error, :already_exists} =
             IntervalScheduler.register(
               is,
               "j",
               {:every, 5, :seconds},
               {JobSink, :ping, [self(), :x]}
             )
  end