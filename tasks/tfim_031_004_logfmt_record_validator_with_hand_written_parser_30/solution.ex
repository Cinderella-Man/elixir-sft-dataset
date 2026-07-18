  test "validate_file returns error for nonexistent file" do
    assert {:error, :file_not_found} =
             LogfmtValidator.validate_file(
               "/tmp/does_not_exist_#{:rand.uniform(999_999)}.log",
               @basic_schema
             )
  end