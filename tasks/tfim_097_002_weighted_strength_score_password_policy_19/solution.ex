  test "accepts a password whose username distance is 4 under the default similarity limit" do
    # "zx9#mqplwt7$wxyz" vs "zx9#mqplwt7$vbn2" differ in exactly the last 4 characters ->
    # Levenshtein distance 4, which is strictly greater than the default limit of 3.
    # len 16 -> 32, all 4 classes -> 40, +20 bonus -> score 92.
    assert PasswordPolicy.evaluate("Zx9#mQpLwT7$WXYZ", %{username: "Zx9#mQpLwT7$vBn2"}) ==
             {:accepted, 92}
  end