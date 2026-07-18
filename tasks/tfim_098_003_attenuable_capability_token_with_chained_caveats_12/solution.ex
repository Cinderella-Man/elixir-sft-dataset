  test "resource_prefix caveat matches by prefix" do
    token = attenuate!(CapabilityToken.mint(@root, "u"), "resource_prefix = /docs/")

    assert :ok = CapabilityToken.authorize(token, @root, %{resource: "/docs/a/b.txt"})
    assert :ok = CapabilityToken.authorize(token, @root, %{resource: "/docs/"})

    assert {:error, {:caveat_failed, "resource_prefix = /docs/"}} =
             CapabilityToken.authorize(token, @root, %{resource: "/secrets/x"})

    assert {:error, {:caveat_failed, "resource_prefix = /docs/"}} =
             CapabilityToken.authorize(token, @root, %{})
  end