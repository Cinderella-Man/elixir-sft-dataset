  test "temporal widening also folds the space-separated datetime form" do
    csv = """
    ts
    2020-01-15
    2020-01-15 10:00:00
    2021-06-30
    """

    assert schema(csv) == %{"ts" => :datetime}
  end