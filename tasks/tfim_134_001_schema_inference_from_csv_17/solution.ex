  test "datetimes with a space separator are recognized" do
    csv = """
    ts
    2020-01-01 12:00:00
    2021-06-15 08:30:45
    """

    assert schema(csv) == %{"ts" => :datetime}
  end