  test "a truncated token is malformed" do
    token = attenuate!(CapabilityToken.mint(@root, "user:1"), "action = read")
    truncated = binary_part(token, 0, div(byte_size(token), 2))
    assert {:error, :malformed} = CapabilityToken.authorize(truncated, @root, %{})
  end