  test "insert with a nil required field returns a missing_fields error" do
    assert {:error, {:missing_fields, fields}} = Factory.insert(:user, name: nil)
    assert :name in fields
  end