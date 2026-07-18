    test "sql_identifier/1" do
      assert {:ok, "users"} = Sanitizer.sql_identifier("us;ers")
      assert {:error, :empty} = Sanitizer.sql_identifier("!!!")
    end