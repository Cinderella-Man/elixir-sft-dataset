  test "boolean detection is case-insensitive across mixed casings" do
    csv = """
    flag
    TRUE
    False
    tRuE
    """

    assert schema(csv) == %{"flag" => :boolean}
  end