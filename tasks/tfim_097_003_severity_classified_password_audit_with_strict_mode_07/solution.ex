  test "username similarity is a warning, not an error, by default" do
    # Differs from the username by one character -> distance 1 (<= 3), otherwise strong.
    report = PasswordPolicy.audit("Xy9#Kw2$Lm", %{username: "Xy9#Kw2$Lp"})

    assert report == %{status: :ok, errors: [], warnings: [:too_similar_to_username]}
  end