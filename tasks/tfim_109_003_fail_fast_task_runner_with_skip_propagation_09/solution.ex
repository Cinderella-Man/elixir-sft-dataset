  test "a dependent starts only after its dependency finishes" do
    ResilientRunner.submit(:runner, :a, func: ok_task(:a, 50))
    ResilientRunner.submit(:runner, :b, depends_on: [:a], func: ok_task(:b, 10))

    assert {:ok, _} = ResilientRunner.run_all(:runner)

    a_end =
      Enum.find_value(Recorder.events(), fn
        {:a, :end, t} -> t
        _ -> nil
      end)

    b_start =
      Enum.find_value(Recorder.events(), fn
        {:b, :start, t} -> t
        _ -> nil
      end)

    assert a_end <= b_start
  end