    test "lenient reports removed illegal chars" do
      assert {:ok, "users", [:removed_illegal_chars]} = Sanitizer.sql_identifier("us;ers")
    end