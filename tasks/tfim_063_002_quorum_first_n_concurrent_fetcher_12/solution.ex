  test "a cancelled source's fetch function is interrupted before it can finish its work" do
    parent = self()

    winner = fn ->
      send(parent, {:started, :w, self()})

      receive do
        :go -> {:ok, :w}
      end
    end

    loser = fn ->
      send(parent, {:started, :slow, self()})

      receive do
        :never -> :ok
      after
        1_000 -> send(parent, {:completed, :slow})
      end

      {:ok, :slow}
    end

    sources = [{:w, winner}, {:slow, loser}]

    caller =
      Task.async(fn -> QuorumFetcher.fetch_first(sources, 1, 5_000) end)

    assert_receive {:started, :w, pid_w}, 1_000
    assert_receive {:started, :slow, _}, 1_000

    send(pid_w, :go)

    result = Task.await(caller, 5_000)

    assert result[:w] == {:ok, :w}
    assert result[:slow] == {:error, :cancelled}
    refute_receive {:completed, :slow}, 1_500
  end