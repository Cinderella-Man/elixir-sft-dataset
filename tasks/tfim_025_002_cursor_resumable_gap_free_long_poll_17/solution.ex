  test "dead subscribers are dropped and do not accumulate", %{server: server} do
    {:ok, agent} = Agent.start(fn -> :ok end)
    Agent.get(agent, fn _ -> Notifications.subscribe(server, "user:1") end)
    ref = Process.monitor(agent)
    Agent.stop(agent)
    assert_receive {:DOWN, ^ref, :process, ^agent, _}, 500

    # Publishing after the subscriber died must still succeed.
    assert {:ok, 1} = Notifications.publish(server, "user:1", %{"n" => 1})
  end