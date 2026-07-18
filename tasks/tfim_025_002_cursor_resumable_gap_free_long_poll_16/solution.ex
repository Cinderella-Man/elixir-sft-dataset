  test "publish to a user with no subscribers does not crash", %{server: server} do
    assert {:ok, 1} = Notifications.publish(server, "nobody", %{"ignored" => true})
  end