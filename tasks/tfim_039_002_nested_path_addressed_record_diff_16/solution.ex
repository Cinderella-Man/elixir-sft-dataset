  test "top-level leaf added and removed both use :missing on the absent side" do
    old = [%{id: 1, name: "A"}, %{id: 2, name: "B", nickname: "Bee"}]
    new = [%{id: 1, name: "A", nickname: "Ace"}, %{id: 2, name: "B"}]

    %{changed: changed} = NestedRecordDiff.diff(old, new)

    assert changes_for(changed, 1) == %{"nickname" => {:missing, "Ace"}}
    assert changes_for(changed, 2) == %{"nickname" => {"Bee", :missing}}
  end