  test "a lowered :max_username_similarity suppresses the similarity warning" do
    # Distance from the username is 2; with the threshold overridden to 1 the
    # password is no longer "too similar", so no warning is raised.
    report =
      PasswordPolicy.audit("Xy9#Kw2$Lm", %{
        username: "Xy9#Kw2$Zz",
        max_username_similarity: 1
      })

    assert report == %{status: :ok, errors: [], warnings: []}
  end