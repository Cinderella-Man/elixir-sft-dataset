  test "two independent tasks are in flight at the same time" do
    me = self()
    ResilientRunner.submit(:runner, :p, func: gate_task(:p, me, :p_val))
    ResilientRunner.submit(:runner, :q, func: gate_task(:q, me, :q_val))

    run = Task.async(fn -> ResilientRunner.run_all(:runner) end)

    # Both must announce while neither has been released: a runner that
    # executes independent tasks one after the other cannot get here.
    assert_receive {:running, first_id, first_pid}, 2_000
    assert_receive {:running, second_id, second_pid}, 2_000
    assert Enum.sort([first_id, second_id]) == [:p, :q]

    send(first_pid, :release)
    send(second_pid, :release)

    assert {:ok, res} = Task.await(run, 5_000)
    assert res.completed == %{p: :p_val, q: :q_val}
    assert res.failed == %{}
    assert res.skipped == []
  end