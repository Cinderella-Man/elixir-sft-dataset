    test "dispatches to Clock.Real when given the module atom" do
      result = Clock.now(Clock.Real)
      assert %DateTime{} = result
    end