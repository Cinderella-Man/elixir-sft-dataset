  test "sample_rows bounds which rows drive the join" do
    csv = """
    ts
    2020-01-15
    2020-01-15
    2020-01-15T10:00:00
    """

    assert schema(csv, sample_rows: 2) == %{"ts" => :date}
    assert schema(csv) == %{"ts" => :datetime}
  end