  test "token is URL-safe (no +, /, or = characters)" do
    token =
      @root
      |> CapabilityToken.mint("user:42")
      |> attenuate!("action = read")

    refute String.contains?(token, "+")
    refute String.contains?(token, "/")
    refute String.contains?(token, "=")
  end