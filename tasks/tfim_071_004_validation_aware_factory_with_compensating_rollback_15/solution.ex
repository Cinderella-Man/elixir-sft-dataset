  test "insert!/2 raises on validation failure" do
    assert_raise ArgumentError, fn -> Factory.insert!(:user, name: nil) end
  end