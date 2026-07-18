  test "sample_rows limits how many data rows influence inference" do
    csv = """
    n
    1
    2
    3.5
    """

    assert schema(csv, sample_rows: 2) == %{"n" => :integer}
    assert schema(csv) == %{"n" => :float}
  end