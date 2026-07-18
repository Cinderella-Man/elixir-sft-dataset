  test "the first unsatisfied caveat in attachment order is reported" do
    token =
      @root
      |> CapabilityToken.mint("u")
      |> attenuate!("action = read")
      |> attenuate!("expires_at = 100")

    # Both caveats fail; the earlier one wins.
    assert {:error, {:caveat_failed, "action = read"}} =
             CapabilityToken.authorize(token, @root, %{action: "write", now: 999})
  end