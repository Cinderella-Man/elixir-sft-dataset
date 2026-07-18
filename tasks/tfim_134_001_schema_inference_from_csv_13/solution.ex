  test "quoted fields containing commas are parsed as a single field" do
    csv = """
    amount,label
    "1,000",x
    "2,000",y
    """

    assert schema(csv) == %{"amount" => :string, "label" => :string}
  end