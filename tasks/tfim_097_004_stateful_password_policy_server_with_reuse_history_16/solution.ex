  test "a transposed username stays 3 edits away and clears a :max_username_similarity of 2" do
    {:ok, pid} =
      PasswordPolicy.start_link(
        min_length: 1,
        max_username_similarity: 2,
        require_uppercase: false,
        require_lowercase: false,
        require_digit: false,
        require_special: false
      )

    # distance("badc", "abcd") == 3: swapping two adjacent pairs costs three
    # edits under Levenshtein, not two. 3 > 2, so this is accepted.
    assert PasswordPolicy.set_password(pid, "abcd", "badc") == :ok
    assert PasswordPolicy.history_count(pid, "abcd") == 1
  end