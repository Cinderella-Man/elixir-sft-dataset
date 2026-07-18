  test "validate_file reads and validates a real file" do
    path = "/tmp/logfmt_test_#{:rand.uniform(999_999)}.log"

    content = """
    level=info host=web01 method=GET duration=42 success=true
    host=web02 duration=bad success=yes
    """

    File.write!(path, content)
    on_exit(fn -> File.rm(path) end)

    assert {:ok, valid, errors} = LogfmtValidator.validate_file(path, @basic_schema)
    assert length(valid) == 1
    assert length(errors) >= 2
  end