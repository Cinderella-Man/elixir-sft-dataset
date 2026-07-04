  test "single top-level heading with one item and no children" do
    md = """
    # Root
    - **x**: desc (a)
    """

    assert parse(md) == [
             %{
               title: "Root",
               level: 1,
               items: [%{name: "x", description: "desc", tags: ["a"]}],
               children: []
             }
           ]
  end