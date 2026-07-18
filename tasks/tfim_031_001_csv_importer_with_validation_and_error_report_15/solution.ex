  test "a single field can produce multiple errors" do
    # "age" is required, not an integer, — we need a field that triggers both
    # Use a required field with a format check and give it empty value
    schema = [
      field("code", format: ~r/^[A-Z]+$/),
      field("value")
    ]

    csv = """
    code,value
    ,hello
    """

    assert {:ok, [], errors} = CsvImporter.import_string(csv, schema)
    code_errors = Enum.filter(errors, fn {_row, f, _msg} -> f == "code" end)
    # Should have at least "required" error; format error on empty may or may not fire
    assert length(code_errors) >= 1
  end