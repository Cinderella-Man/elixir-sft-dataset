    test "prepends underscore when result starts with a digit" do
      assert {:ok, "_1table"} = Sanitizer.sql_identifier("1table")
      assert {:ok, "_99problems"} = Sanitizer.sql_identifier("99problems")
    end