    test "strips dangerous characters" do
      assert {:ok, "users"} = Sanitizer.sql_identifier("us;ers")
      assert {:ok, "tablename"} = Sanitizer.sql_identifier("table--name")
      # Quotes, spaces, and = are stripped; letters and digits survive → "colOR11"
      assert {:ok, "colOR11"} = Sanitizer.sql_identifier("col' OR '1'='1")
    end