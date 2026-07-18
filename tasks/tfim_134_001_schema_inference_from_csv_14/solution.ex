  test "booleans are matched case-insensitively" do
    csv = """
    flag
    TRUE
    False
    """

    assert schema(csv) == %{"flag" => :boolean}
  end