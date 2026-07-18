  test "every source has started before any of them is allowed to complete" do
    parent = self()

    gated = fn name ->
      fn ->
        send(parent, {:started, name, self()})

        receive do
          :go -> {:ok, name}
        end
      end
    end

    sources = [{:a, gated.(:a)}, {:b, gated.(:b)}, {:c, gated.(:c)}]

    caller =
      Task.async(fn -> QuorumFetcher.fetch_first(sources, 1, 5_000) end)

    assert_receive {:started, :a, pid_a}, 1_000
    assert_receive {:started, :b, _}, 1_000
    assert_receive {:started, :c, _}, 1_000

    send(pid_a, :go)

    result = Task.await(caller, 5_000)

    assert result[:a] == {:ok, :a}
    assert result[:b] == {:error, :cancelled}
    assert result[:c] == {:error, :cancelled}
  end