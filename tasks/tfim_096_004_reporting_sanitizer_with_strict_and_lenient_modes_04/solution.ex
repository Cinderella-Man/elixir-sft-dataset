    test "lenient reports digit-start prefixing" do
      assert {:ok, "_1table", [:prefixed_digit_start]} = Sanitizer.sql_identifier("1table")
    end