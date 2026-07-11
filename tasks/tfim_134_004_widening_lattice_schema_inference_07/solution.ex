  test "a column of pure datetimes stays datetime" do
    csv = """
    ts
    2020-01-01 12:00:00
    2021-06-15T08:30:45
    """

    assert schema(csv) == %{"ts" => :datetime}
  end