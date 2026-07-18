  test "lists all four rejection reasons together in canonical order" do
    # "abc": len 3 -> 6, lowercase only -> 10, score 16.
    # Short (< default 8), on the common list (matched case-insensitively against "ABC"),
    # Levenshtein distance 1 from "abd" (<= default 3), and score 16 < default 60.
    result =
      PasswordPolicy.evaluate("abc", %{
        username: "abd",
        common_passwords: ["ABC"]
      })

    assert result ==
             {:rejected, 16,
              [:too_short, :common_password, :too_similar_to_username, :insufficient_strength]}
  end