    test "successive calls move forward (or stay equal)" do
      t1 = Clock.Real.now()
      t2 = Clock.Real.now()
      assert DateTime.compare(t2, t1) in [:gt, :eq]
    end