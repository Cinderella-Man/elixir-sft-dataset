  test "reports every missing required field" do
    assert {:error, {:missing_fields, fields}} =
             Factory.insert(:user, name: nil, email: nil)

    assert :name in fields
    assert :email in fields
  end