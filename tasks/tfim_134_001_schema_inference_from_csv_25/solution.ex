  test "a datetime with an impossible calendar date falls back to string" do
    csv = """
    ts
    2020-02-30T10:00:00
    2021-01-01 24:00:00
    """

    assert schema(csv) == %{"ts" => :string}
  end