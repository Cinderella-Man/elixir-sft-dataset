  test "valid? is true for a complete struct and false for a missing field" do
    assert Factory.valid?(:user)
    refute Factory.valid?(:user, email: nil)
  end