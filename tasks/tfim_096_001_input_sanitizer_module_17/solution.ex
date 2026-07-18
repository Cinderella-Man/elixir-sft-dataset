    test "returns error for empty result after stripping" do
      assert {:error, :empty} = Sanitizer.sql_identifier(";;;")
      assert {:error, :empty} = Sanitizer.sql_identifier("")
      assert {:error, :empty} = Sanitizer.sql_identifier("---")
    end