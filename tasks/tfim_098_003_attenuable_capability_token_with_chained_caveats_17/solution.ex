  test "attenuation only narrows: adding a caveat can never re-open a denial" do
    token =
      @root
      |> CapabilityToken.mint("u")
      |> attenuate!("action = read")
      |> attenuate!("action = write")

    # Contradictory caveats: nothing satisfies both.
    assert {:error, {:caveat_failed, "action = read"}} =
             CapabilityToken.authorize(token, @root, %{action: "write"})

    assert {:error, {:caveat_failed, "action = write"}} =
             CapabilityToken.authorize(token, @root, %{action: "read"})
  end