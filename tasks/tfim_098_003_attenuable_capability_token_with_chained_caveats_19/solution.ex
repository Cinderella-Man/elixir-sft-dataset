  test "tokens do not cross-verify between root keys" do
    a = attenuate!(CapabilityToken.mint("key-a", "u"), "action = read")
    b = attenuate!(CapabilityToken.mint("key-b", "u"), "action = read")

    assert :ok = CapabilityToken.authorize(a, "key-a", %{action: "read"})
    assert :ok = CapabilityToken.authorize(b, "key-b", %{action: "read"})
    assert {:error, :invalid_signature} = CapabilityToken.authorize(a, "key-b", %{action: "read"})
    assert {:error, :invalid_signature} = CapabilityToken.authorize(b, "key-a", %{action: "read"})
  end