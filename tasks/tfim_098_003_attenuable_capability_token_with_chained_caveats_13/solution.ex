  test "unknown caveat keys fail closed" do
    token = attenuate!(CapabilityToken.mint(@root, "u"), "ip_range = 10.0.0.0/8")

    assert {:error, {:caveat_failed, "ip_range = 10.0.0.0/8"}} =
             CapabilityToken.authorize(token, @root, %{now: 1, action: "read"})
  end