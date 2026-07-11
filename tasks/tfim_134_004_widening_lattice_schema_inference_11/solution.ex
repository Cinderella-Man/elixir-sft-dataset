  test "quoted values are strings regardless of contents" do
    csv = """
    code
    "2020-01-15"
    "2020-01-15T10:00:00"
    """

    assert schema(csv) == %{"code" => :string}
  end