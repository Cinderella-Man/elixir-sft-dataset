    property "always produces a JSON scalar of depth 0" do
      check all(v <- JsonGenerators.scalar()) do
        assert scalar?(v)
        assert depth(v) == 0
      end
    end