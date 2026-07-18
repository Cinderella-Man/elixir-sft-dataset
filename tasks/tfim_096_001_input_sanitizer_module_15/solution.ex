    test "allows alphanumeric and underscore" do
      assert {:ok, "users"} = Sanitizer.sql_identifier("users")
      assert {:ok, "user_name"} = Sanitizer.sql_identifier("user_name")
      assert {:ok, "col1"} = Sanitizer.sql_identifier("col1")
    end