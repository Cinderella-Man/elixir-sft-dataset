  test "rejects when the username distance exactly equals max_username_similarity" do
    # Password and username differ in their last 3 characters -> Levenshtein distance 3,
    # which is <= the default max_username_similarity of 3 -> rejection.
    # len 16 -> 32, all 4 classes -> 40, +20 bonus -> score 92.
    assert PasswordPolicy.evaluate("Zx9#mQpLwT7$vXYZ", %{username: "Zx9#mQpLwT7$vBn2"}) ==
             {:rejected, 92, [:too_similar_to_username]}
  end