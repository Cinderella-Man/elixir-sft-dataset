  test "a token issued by another server (different secret) is :invalid_signature",
       %{server: server} do
    other =
      start_supervised!(
        Supervisor.child_spec(
          {SingleUseToken, secret: "different-secret", clock: &Clock.now/0},
          id: :other_server
        )
      )

    token = SingleUseToken.issue(server, "x", 300)
    assert {:error, :invalid_signature} = SingleUseToken.redeem(other, token)
  end