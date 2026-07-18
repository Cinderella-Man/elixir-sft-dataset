  test "filename reports all five violations in the documented fixed order" do
    assert {:ok, "abc.d",
            [
              :removed_null_bytes,
              :removed_path_separators,
              :removed_illegal_chars,
              :collapsed_dots,
              :trimmed_dots
            ]} = Sanitizer.filename(".\0.a b/c..d.")
  end