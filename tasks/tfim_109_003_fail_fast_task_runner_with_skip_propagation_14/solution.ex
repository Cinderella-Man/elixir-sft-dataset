  test "siblings sharing a dependency are in flight at the same time" do
    me = self()
    ResilientRunner.submit(:runner, :root, func: ok_task(:root, 0, :root_val))
    ResilientRunner.submit(:runner, :b, depends_on: [:root], func: gate_task(:b, me, :b_val))
    ResilientRunner.submit(:runner, :c, depends_on: [:root], func: gate_task(:c, me, :c_val))

    run = Task.async(fn -> ResilientRunner.run_all(:runner) end)

    # Once their shared dependency has finished, both dependents become ready
    # and must overlap rather than take turns.
    assert_receive {:running, first_id, first_pid}, 2_000
    assert_receive {:running, second_id, second_pid}, 2_000
    assert Enum.sort([first_id, second_id]) == [:b, :c]

    send(first_pid, :release)
    send(second_pid, :release)

    assert {:ok, res} = Task.await(run, 5_000)
    assert res.completed == %{root: :root_val, b: :b_val, c: :c_val}
    assert res.failed == %{}
    assert res.skipped == []
  end