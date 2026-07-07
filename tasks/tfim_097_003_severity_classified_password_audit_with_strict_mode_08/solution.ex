  test "username similarity becomes an error under strict mode" do
    report = PasswordPolicy.audit("Xy9#Kw2$Lm", %{username: "Xy9#Kw2$Lp", strict: true})

    assert report == %{status: :error, errors: [:too_similar_to_username], warnings: []}
  end