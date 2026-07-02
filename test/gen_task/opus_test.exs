defmodule GenTask.OpusTest do
  use ExUnit.Case, async: true

  alias GenTask.Opus

  defp json(map), do: Jason.encode!(map)

  describe "classify/2 — success" do
    test "exit 0, is_error false, returns the .result text + meta" do
      out =
        json(%{
          "type" => "result",
          "subtype" => "success",
          "is_error" => false,
          "result" => "<file path=\"solution.ex\">\ndefmodule Foo do\nend\n</file>",
          "stop_reason" => "end_turn",
          "usage" => %{"input_tokens" => 100, "output_tokens" => 42},
          "total_cost_usd" => 0.01,
          "num_turns" => 1
        })

      assert {:ok, text, meta} = Opus.classify(out, 0)
      assert text =~ "defmodule Foo"
      assert meta.stop_reason == "end_turn"
      assert meta.usage["output_tokens"] == 42
      assert meta.is_error == false
    end

    test "empty .result normalizes to an empty string" do
      out = json(%{"is_error" => false, "subtype" => "success", "stop_reason" => "end_turn"})
      assert {:ok, "", _meta} = Opus.classify(out, 0)
    end

    test "decodes when JSON is the last line among log noise" do
      out = "loading...\nsome log\n" <> json(%{"is_error" => false, "result" => "hi"})
      assert {:ok, "hi", _meta} = Opus.classify(out, 0)
    end
  end

  describe "classify/2 — usage limit" do
    test "detected via api_error_status 429" do
      out = json(%{"is_error" => true, "api_error_status" => 429, "result" => "boom"})
      assert {:usage_limit, _meta} = Opus.classify(out, 1)
    end

    test "detected via a usage-limit message" do
      out =
        json(%{
          "is_error" => true,
          "subtype" => "error",
          "result" => "5-hour usage limit reached; resets at 3pm"
        })

      assert {:usage_limit, _meta} = Opus.classify(out, 1)
    end

    test "detected via a rate-limit message" do
      out = json(%{"is_error" => true, "result" => "rate limit exceeded, try again later"})
      assert {:usage_limit, _meta} = Opus.classify(out, 1)
    end

    test "call/3 gives up once the cumulative usage-wait cap is exceeded" do
      logs = Path.join(System.tmp_dir!(), "opus_test_#{System.unique_integer([:positive])}")

      runner = fn _sys, _user, _cfg ->
        {json(%{"is_error" => true, "api_error_status" => 429, "result" => "usage limit reached"}),
         1}
      end

      cfg = %GenTask.Config{
        opus_runner: runner,
        usage_wait_ms: 1,
        usage_max_wait_ms: 2,
        logs_dir: logs
      }

      assert {:error, {:usage_limit, :exhausted}} = Opus.call("sys", "user", cfg)
    after
      :ok
    end
  end

  describe "classify/2 — transient" do
    test "detected via an overloaded message" do
      out = json(%{"is_error" => true, "subtype" => "error", "result" => "server overloaded"})
      assert {:transient, reason} = Opus.classify(out, 1)
      assert reason =~ "overloaded"
    end

    test "a gateway error saying 'try again' is transient, NOT a usage limit" do
      # Regression guard: bare "try again" must never route to the uncapped
      # usage-limit sleep loop (it appears in 5xx/gateway bodies).
      out =
        json(%{
          "is_error" => true,
          "api_error_status" => 503,
          "subtype" => "error",
          "result" => "upstream error, please try again later"
        })

      assert {:transient, _reason} = Opus.classify(out, 1)
    end

    test "detected via a 5xx api_error_status" do
      out = json(%{"is_error" => true, "api_error_status" => 503, "result" => "bad gateway"})
      assert {:transient, _reason} = Opus.classify(out, 1)
    end

    test "no parseable JSON (killed/crashed) is transient" do
      assert {:transient, reason} = Opus.classify("Killed\n", 137)
      assert reason =~ "no JSON"
    end

    test "clean JSON, no error flag, but a non-zero exit is transient" do
      out = json(%{"is_error" => false, "result" => "partial"})
      assert {:transient, reason} = Opus.classify(out, 2)
      assert reason =~ "non-zero exit 2"
    end
  end

  describe "classify/2 — truncation & refusal" do
    test "stop_reason max_tokens is truncated" do
      out = json(%{"is_error" => false, "stop_reason" => "max_tokens", "result" => "half"})
      assert {:truncated, _meta} = Opus.classify(out, 0)
    end

    test "a content refusal is classified as refusal" do
      out =
        json(%{
          "is_error" => true,
          "subtype" => "error",
          "result" => "I cannot assist with that."
        })

      assert {:refusal, reason} = Opus.classify(out, 1)
      assert reason =~ "cannot assist"
    end
  end
end
