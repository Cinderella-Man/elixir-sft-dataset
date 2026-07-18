  test "interleaved inserts and removes keep the tree balanced and consistent" do
    {:ok, srv} = IntervalRegistry.start_link()
    half = div(@big, 2)

    task =
      Task.async(fn ->
        ids =
          Enum.map(1..@big, fn i ->
            {:ok, id} = IntervalRegistry.insert(srv, {i, i + 3})
            {i, id}
          end)

        Enum.each(ids, fn {i, id} ->
          if i > half, do: :ok = IntervalRegistry.remove(srv, id)
        end)

        :done
      end)

    assert {:ok, :done} = Task.yield(task, 30_000) || Task.shutdown(task, :brutal_kill)

    assert IntervalRegistry.size(srv) == half
    assert IntervalRegistry.overlapping(srv, {half + 4, @big}) == []

    assert IntervalRegistry.enclosing(srv, half) == [
             {half - 3, half},
             {half - 2, half + 1},
             {half - 1, half + 2},
             {half, half + 3}
           ]

    assert IntervalRegistry.stab_count(srv, half) == 4

    assert :ok = IntervalRegistry.stop(srv)
  end