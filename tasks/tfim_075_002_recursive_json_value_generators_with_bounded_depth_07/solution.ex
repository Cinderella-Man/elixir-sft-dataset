    property "strings are alphanumeric and at most 8 chars" do
      check all(v <- JsonGenerators.scalar()) do
        if is_binary(v) do
          assert String.length(v) <= 8
          assert v == "" or String.match?(v, ~r/^[a-zA-Z0-9]+$/)
        end
      end
    end