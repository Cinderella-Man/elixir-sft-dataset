  test "empty string returns empty categories and errors" do
    assert parse("") == %{categories: [], errors: []}
  end