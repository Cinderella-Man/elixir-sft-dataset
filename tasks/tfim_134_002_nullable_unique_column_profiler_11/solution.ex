  test "sample_rows limits both type and profile computation" do
    csv = """
    n
    1
    2
    2
    """

    # first two rows only: no duplicates seen, no float seen
    assert schema(csv, sample_rows: 2) == %{
             "n" => %{type: :integer, nullable: false, unique: true}
           }

    assert schema(csv) == %{"n" => %{type: :integer, nullable: false, unique: false}}
  end