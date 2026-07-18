    property "all keys are non-empty alphanumeric strings" do
      check all(obj <- JsonGenerators.object(StreamData.integer(), 5)) do
        for {k, _v} <- obj do
          assert is_binary(k)
          assert k != ""
          assert String.match?(k, ~r/^[a-zA-Z0-9]+$/)
        end
      end
    end