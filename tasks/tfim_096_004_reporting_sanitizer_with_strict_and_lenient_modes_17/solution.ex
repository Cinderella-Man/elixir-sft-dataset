    test "reports removed control chars" do
      assert {:ok, "ab", [:removed_control_chars]} = Sanitizer.text("a\x01b")
    end