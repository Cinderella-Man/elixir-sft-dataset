  test "max_username_similarity defaults to 3 when the option is omitted" do
    # distance("Xyz9!abc", "Xyz9!qrs") == 3, i.e. exactly at the default threshold.
    assert {:error, errs} = PasswordPolicy.validate("Xyz9!abc", %{username: "Xyz9!qrs"})
    assert Enum.sort(errs) == Enum.sort([:too_similar_to_username])

    # distance("Xyz9!abc", "Xyz9!qrst") == 4, strictly greater than the default threshold.
    assert PasswordPolicy.validate("Xyz9!abc", %{username: "Xyz9!qrst"}) == :ok
  end