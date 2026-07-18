    test "uses real clock when Clock.Real is injected" do
      # Just verify it doesn't crash and returns a plausible string
      result = Greeter.greet("Dave", clock: Clock.Real)
      assert result =~ ~r/Good (morning|afternoon|evening), Dave!/
    end