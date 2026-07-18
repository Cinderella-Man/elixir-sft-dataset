  test "quoted numbers are strings, not integers" do
    csv = """
    code
    "123"
    "456"
    """

    assert schema(csv) == %{"code" => :string}
  end