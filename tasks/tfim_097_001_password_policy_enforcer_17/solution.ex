  test "password identical to username is rejected" do
    # "carol" is 5 chars and min_length defaults to 8, so :too_short fires alongside
    # the similarity violation (distance 0 <= 3).
    result =
      PasswordPolicy.validate("carol", %{
        username: "carol",
        require_uppercase: false,
        require_lowercase: false,
        require_digit: false,
        require_special: false,
        max_username_similarity: 3
      })

    assert Enum.sort(violations(result)) == Enum.sort([:too_short, :too_similar_to_username])
  end