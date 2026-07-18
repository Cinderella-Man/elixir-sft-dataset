  test "queued sources start in list order as slots free up" do
    parent = self()

    gate = fn name ->
      fn ->
        send(parent, {:started, name, self()})

        receive do
          :release -> {:ok, name}
        end
      end
    end

    sources = for n <- [:s1, :s2, :s3, :s4], do: {n, gate.(n)}
    runner = Task.async(fn -> PooledFetcher.fetch_all(sources, 2, 5_000) end)

    assert_receive {:started, :s1, p1}, 1_000
    assert_receive {:started, :s2, p2}, 1_000
    refute_receive {:started, :s3, _}, 100

    send(p1, :release)
    assert_receive {:started, :s3, p3}, 1_000
    refute_receive {:started, :s4, _}, 100

    send(p2, :release)
    assert_receive {:started, :s4, p4}, 1_000

    send(p3, :release)
    send(p4, :release)

    assert Task.await(runner, 5_000) ==
             %{s1: {:ok, :s1}, s2: {:ok, :s2}, s3: {:ok, :s3}, s4: {:ok, :s4}}
  end