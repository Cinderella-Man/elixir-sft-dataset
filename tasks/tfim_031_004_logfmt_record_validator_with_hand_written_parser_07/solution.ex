  test "key with = but empty value produces empty string" do
    schema = [field("msg", required: false), field("level")]
    input = "level=info msg=\n"

    assert {:ok, [row], []} = LogfmtValidator.validate_string(input, schema)
    assert row["msg"] == ""
  end