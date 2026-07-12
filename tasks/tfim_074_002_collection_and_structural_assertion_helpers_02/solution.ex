    test "passes for a list sorted ascending by key" do
      people = [%{name: "A", age: 20}, %{name: "B", age: 30}, %{name: "C", age: 40}]
      assert_sorted_by(people, & &1.age)
    end