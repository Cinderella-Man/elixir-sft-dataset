    test "violations come in fixed order" do
      assert {:ok, "_1a", [:removed_illegal_chars, :prefixed_digit_start]} =
               Sanitizer.sql_identifier("1;a")
    end