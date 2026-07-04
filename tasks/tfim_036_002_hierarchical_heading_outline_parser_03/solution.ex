  test "deeper heading becomes a child of the shallower heading" do
    md = """
    # Parent
    - **p**: pd (a, b)
    ## Child
    - **c**: cd
    """

    assert parse(md) == [
             %{
               title: "Parent",
               level: 1,
               items: [%{name: "p", description: "pd", tags: ["a", "b"]}],
               children: [
                 %{
                   title: "Child",
                   level: 2,
                   items: [%{name: "c", description: "cd", tags: []}],
                   children: []
                 }
               ]
             }
           ]
  end