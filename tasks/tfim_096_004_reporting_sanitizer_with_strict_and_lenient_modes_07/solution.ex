    test "empty result is a hard error in both modes" do
      assert {:error, [:empty]} = Sanitizer.sql_identifier("!!!")
      assert {:error, [:empty]} = Sanitizer.sql_identifier("!!!", mode: :strict)
    end