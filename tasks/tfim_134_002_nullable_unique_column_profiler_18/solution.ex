  test "real calendar dates and datetimes classify while impossible dates fall back to string" do
    csv = """
    d,ts,bad,flag
    2020-01-31,2020-01-31T10:00:00,2020-02-30,TRUE
    03/04/2021,2021-03-04 08:30:00,13/01/2021,False
    """

    result = schema(csv)
    assert result["d"] == %{type: :date, nullable: false, unique: true}
    assert result["ts"] == %{type: :datetime, nullable: false, unique: true}
    assert result["bad"] == %{type: :string, nullable: false, unique: true}
    assert result["flag"] == %{type: :boolean, nullable: false, unique: true}
  end