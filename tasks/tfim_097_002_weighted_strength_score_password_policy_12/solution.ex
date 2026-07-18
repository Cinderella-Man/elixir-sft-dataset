  test "the +20 length bonus requires at least 16 characters, not 15" do
    # "Zx9#mQpLwT7$vBn": len 15 -> 30, all 4 classes -> 40, NO bonus -> score 70.
    assert PasswordPolicy.evaluate("Zx9#mQpLwT7$vBn", %{username: "operator"}) ==
             {:accepted, 70}
  end