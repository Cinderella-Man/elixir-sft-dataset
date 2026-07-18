  test "publish with no subscribers does not crash", %{server: server} do
    assert :ok = Notifications.publish(server, "nobody", "chan", %{"ignored" => true})
  end