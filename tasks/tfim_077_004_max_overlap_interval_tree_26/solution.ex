  test "tree is inert data: no registered process, no behaviour, usable from another process" do
    tree = Enum.reduce(1..50, T.new(), fn i, acc -> T.insert(acc, {i, i + 3}) end)

    refute is_pid(tree)
    refute is_reference(tree)
    refute is_port(tree)

    behaviours =
      T.module_info(:attributes)
      |> Keyword.get_values(:behaviour)
      |> List.flatten()

    refute GenServer in behaviours
    assert Process.whereis(MaxOverlapIntervalTree) == nil

    task =
      Task.async(fn ->
        {T.max_overlap(tree), T.busiest_point(tree), T.depth_at(tree, 10)}
      end)

    assert Task.await(task, 1_000) == {4, 4, 4}
  end