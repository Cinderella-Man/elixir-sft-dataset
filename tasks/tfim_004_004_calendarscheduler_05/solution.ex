  test "unregister / jobs / next_run", %{cs: cs} do
    assert {:error, :not_found} = CalendarScheduler.next_run(cs, "ghost")
    assert {:error, :not_found} = CalendarScheduler.unregister(cs, "ghost")

    :ok =
      CalendarScheduler.register(
        cs,
        "j",
        {:nth_day_of_month, 15, {12, 0}},
        {JobSink, :ping, [self(), :j]}
      )

    assert [{"j", {:nth_day_of_month, 15, {12, 0}}, _}] = CalendarScheduler.jobs(cs)
    assert :ok = CalendarScheduler.unregister(cs, "j")
    assert {:error, :not_found} = CalendarScheduler.next_run(cs, "j")
  end