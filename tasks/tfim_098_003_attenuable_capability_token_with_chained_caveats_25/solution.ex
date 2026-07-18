  test "signature check precedes caveat evaluation" do
    token = attenuate!(CapabilityToken.mint(@root, "u"), "expires_at = 1")

    # Expired AND wrong key -> the signature failure is reported.
    assert {:error, :invalid_signature} =
             CapabilityToken.authorize(token, "wrong-key", %{now: 10_000})
  end