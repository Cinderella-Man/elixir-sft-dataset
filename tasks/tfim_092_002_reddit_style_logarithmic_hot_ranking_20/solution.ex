  test "divisor magnitude flips whether time or votes dominate the ranking" do
    votes = item(id: :votes, upvotes: 100, created_at: @epoch)
    fresh = item(id: :fresh, upvotes: 1, created_at: @epoch + 45_000)

    # small divisor: 45_000 seconds is worth 3.0, beating the 2.0 vote term
    assert ids(Ranking.rank([votes, fresh], epoch: @epoch, divisor: 15_000)) == [:fresh, :votes]

    # large divisor: 45_000 seconds is worth only 0.1, so votes win
    assert ids(Ranking.rank([fresh, votes], epoch: @epoch, divisor: 450_000)) == [:votes, :fresh]
  end