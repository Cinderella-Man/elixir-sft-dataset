  test "followers are handed the leader's value and never run their own fallback", %{cl: cl} do
    parent = self()

    leader_fun = fn ->
      send(parent, {:leading, self()})

      receive do
        :go -> :leader_value
      end
    end

    leader = Task.async(fn -> CacheLayer.fetch(cl, :t, :shared, leader_fun) end)
    assert_receive {:leading, leader_pid}, 1_000

    # Every follower passes a fallback that must never be invoked: whether it
    # parks behind the leader or arrives after the insert, the value it gets
    # must be the LEADER's value.
    followers =
      for _ <- 1..5 do
        Task.async(fn ->
          CacheLayer.fetch(cl, :t, :shared, fn -> raise "follower fallback must not run" end)
        end)
      end

    send(leader_pid, :go)

    assert {:ok, :leader_value} = Task.await(leader, 2_000)

    for f <- followers do
      assert {:ok, :leader_value} = Task.await(f, 2_000)
    end
  end