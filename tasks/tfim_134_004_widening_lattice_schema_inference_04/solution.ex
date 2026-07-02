  test "temporal widening: a mix of dates and datetimes becomes datetime" do
    csv = """
    ts
    2020-01-15
    2020-01-15T10:00:00
    """

    assert schema(csv) == %{"ts" => :datetime}
  end