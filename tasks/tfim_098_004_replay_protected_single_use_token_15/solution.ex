  test "the omitted :clock defaults to Unix epoch seconds" do
    secret = "epoch-secret"
    now = System.os_time(:second)

    # Issues on the default clock; the two peers share the secret, so the tokens
    # verify there and are judged against a known epoch-second time.
    issuer =
      start_supervised!(
        Supervisor.child_spec({SingleUseToken, secret: secret}, id: :epoch_issuer)
      )

    present_peer =
      start_supervised!(
        Supervisor.child_spec({SingleUseToken, secret: secret, clock: fn -> now end},
          id: :epoch_present_peer
        )
      )

    future_peer =
      start_supervised!(
        Supervisor.child_spec({SingleUseToken, secret: secret, clock: fn -> now + 3_600 end},
          id: :epoch_future_peer
        )
      )

    # A 60-second token issued "now" is still valid at epoch second `now` ...
    assert {:ok, "epoch"} =
             SingleUseToken.redeem(present_peer, SingleUseToken.issue(issuer, "epoch", 60))

    # ... and expired an hour later, which only holds if the default clock ticks
    # in epoch seconds rather than some other unit or epoch.
    assert {:error, :expired} =
             SingleUseToken.redeem(future_peer, SingleUseToken.issue(issuer, "epoch", 60))
  end