  test "too similar to username - distance <= threshold" do
    # Levenshtein("user1234!", "user") == 5, so the threshold must be >= 5 for the
    # similarity rule to reject (boundary: distance == threshold).
    result =
      PasswordPolicy.validate("user1234!", %{
        username: "user",
        require_uppercase: false,
        max_username_similarity: 5
      })

    assert Enum.sort(violations(result)) == Enum.sort([:too_similar_to_username])
  end