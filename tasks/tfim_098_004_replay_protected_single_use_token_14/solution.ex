  test "server started without :clock issues and redeems tokens" do
    server =
      start_supervised!(
        Supervisor.child_spec({SingleUseToken, secret: "default-clock-secret"},
          id: :default_clock_server
        )
      )

    token = SingleUseToken.issue(server, %{user_id: 3}, 300)
    assert {:ok, %{user_id: 3}} = SingleUseToken.redeem(server, token)
    assert {:error, :replayed} = SingleUseToken.redeem(server, token)
  end