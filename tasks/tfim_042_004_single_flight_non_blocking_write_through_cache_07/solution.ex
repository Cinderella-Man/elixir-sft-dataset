  test "if the leader crashes, a waiting follower retries and succeeds", %{cl: cl} do
    parent = self()

    # The leader signals, then crashes without producing a value.
    crashing = fn ->
      send(parent, :leader_ready)
      Process.sleep(30)
      raise "boom"
    end

    leader =
      Task.async(fn ->
        try do
          CacheLayer.fetch(cl, :t, :k, crashing)
        rescue
          _ -> :crashed
        end
      end)

    receive do
      :leader_ready -> :ok
    after
      1_000 -> flunk("leader never started")
    end

    # A follower joins while the leader is still "computing".
    follower =
      Task.async(fn -> CacheLayer.fetch(cl, :t, :k, fn -> :recovered end) end)

    assert :crashed = Task.await(leader)
    assert {:ok, :recovered} = Task.await(follower, 2_000)
  end