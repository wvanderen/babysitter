defmodule Babysitter.StuckDetectionTest do
  use ExUnit.Case, async: true
  alias Babysitter.StuckDetection
  alias Babysitter.StuckDetection.Detection

  describe "analyze/3" do
    test "returns not stuck for normal output" do
      output = "Reading file: test.txt\nWriting file: output.txt"
      result = StuckDetection.analyze(output)
      refute Detection.stuck?(result)
    end

    test "detects infinite loop patterns" do
      output = "while (true) {\n  doSomething()\n}"
      result = StuckDetection.analyze(output)
      assert Detection.stuck?(result)
      assert result.reason == :infinite_loop
      assert result.severity == :high
    end

    test "detects Python infinite loop" do
      output = "while True:\n    process()"
      result = StuckDetection.analyze(output)
      assert Detection.stuck?(result)
      assert result.reason == :infinite_loop
    end

    test "detects error loops" do
      output = """
      Error: Connection refused
      Retrying...
      Error: Connection refused
      Retrying...
      Error: Connection refused
      """

      result = StuckDetection.analyze(output)
      assert Detection.stuck?(result)
      assert result.reason == :error_loop
      assert result.severity == :high
    end

    test "detects command loops" do
      output = """
      $ npm test
      Running tests...
      $ npm test
      Running tests...
      $ npm test
      Running tests...
      """

      result = StuckDetection.analyze(output)
      assert Detection.stuck?(result)
      assert result.reason == :command_loop
      assert result.severity == :medium
    end

    test "detects repetitive output" do
      output = String.duplicate("Waiting for response...\n", 10)
      result = StuckDetection.analyze(output)
      assert Detection.stuck?(result)
      assert result.reason == :repetitive_output
      assert result.severity == :medium
    end

    test "returns none for short output" do
      output = "Short\noutput"
      result = StuckDetection.analyze(output)
      refute Detection.stuck?(result)
    end

    test "respects min_lines_for_analysis config" do
      output = String.duplicate("Repeated line\n", 5)
      result = StuckDetection.analyze(output, %{}, config: %{min_lines_for_analysis: 3})
      assert Detection.stuck?(result)

      result = StuckDetection.analyze(output, %{}, config: %{min_lines_for_analysis: 20})
      refute Detection.stuck?(result)
    end

    test "detects no progress timeout" do
      last_activity = DateTime.add(DateTime.utc_now(), -400, :second)
      result = StuckDetection.analyze("some output", %{last_activity: last_activity})
      assert Detection.stuck?(result)
      assert result.reason == :no_progress
      assert result.severity == :low
    end

    test "respects no_progress_timeout_ms config" do
      last_activity = DateTime.add(DateTime.utc_now(), -10, :second)

      result =
        StuckDetection.analyze("some output", %{last_activity: last_activity},
          config: %{no_progress_timeout_ms: 5_000}
        )

      assert Detection.stuck?(result)

      result =
        StuckDetection.analyze("some output", %{last_activity: last_activity},
          config: %{no_progress_timeout_ms: 60_000}
        )

      refute Detection.stuck?(result)
    end

    test "detects output stall" do
      history = String.duplicate("Processing data\n", 1000)
      output = "Minimal new output"
      context = %{history: history, time_diff_s: 60}
      result = StuckDetection.analyze(output, context)
      assert Detection.stuck?(result)
      assert result.reason == :output_stall
      assert result.severity == :low
    end
  end

  describe "Detection struct" do
    test "none/0 creates a non-stuck detection" do
      detection = Detection.none()
      refute detection.stuck
      assert detection.severity == :none
      assert detection.reason == :none
    end

    test "detected/4 creates a stuck detection" do
      detection = Detection.detected(:high, :error_loop, %{count: 3}, 0.85)
      assert detection.stuck
      assert detection.severity == :high
      assert detection.reason == :error_loop
      assert detection.confidence == 0.85
    end

    test "stuck?/1 returns correct boolean" do
      assert Detection.stuck?(Detection.detected(:low, :repetitive_output, %{}, 0.5))
      refute Detection.stuck?(Detection.none())
    end

    test "needs_intervention?/1 returns true for medium or higher severity" do
      refute Detection.needs_intervention?(Detection.none())
      refute Detection.needs_intervention?(Detection.detected(:low, :no_progress, %{}, 0.5))
      assert Detection.needs_intervention?(Detection.detected(:medium, :command_loop, %{}, 0.7))
      assert Detection.needs_intervention?(Detection.detected(:high, :error_loop, %{}, 0.9))

      assert Detection.needs_intervention?(
               Detection.detected(:critical, :infinite_loop, %{}, 0.95)
             )
    end
  end

  describe "stuck?/3" do
    test "returns boolean for infinite loop detection" do
      assert StuckDetection.stuck?("while (true) { }")
      refute StuckDetection.stuck?("Normal processing output")
    end

    test "returns boolean for repetitive output" do
      assert StuckDetection.stuck?(String.duplicate("Same\n", 10))
    end
  end

  describe "needs_intervention?/3" do
    test "returns true for high severity issues" do
      output = "Error: Failed\nError: Failed\nError: Failed"
      assert StuckDetection.needs_intervention?(output)
    end

    test "returns false for non-stuck output" do
      output = "Processing file 1\nProcessing file 2\nProcessing file 3"
      refute StuckDetection.needs_intervention?(output)
    end
  end

  describe "confidence calculation" do
    test "higher error counts increase confidence" do
      low_errors = "Error: Failed\nError: Failed\nError: Failed"

      high_errors =
        "Error: Failed\nError: Failed\nError: Failed\nError: Failed\nError: Failed\nError: Failed"

      low_result = StuckDetection.analyze(low_errors)
      high_result = StuckDetection.analyze(high_errors)

      assert high_result.confidence > low_result.confidence
    end

    test "repetitive output has reasonable confidence" do
      output = String.duplicate("Repeated\n", 30)
      result = StuckDetection.analyze(output)

      assert result.confidence >= 0.55
      assert result.confidence <= 0.85
    end
  end

  describe "command extraction" do
    test "detects $ prefix commands" do
      output = "$ npm test\n$ npm test\n$ npm test"
      result = StuckDetection.analyze(output)
      assert result.reason == :command_loop
      assert result.details.command == "npm test"
    end

    test "detects > prefix commands" do
      output = "> run tests\n> run tests\n> run tests"
      result = StuckDetection.analyze(output)
      assert result.reason == :command_loop
    end

    test "detects Running: prefix commands" do
      output = "Running: make build\nRunning: make build\nRunning: make build"
      result = StuckDetection.analyze(output)
      assert result.reason == :command_loop
    end
  end

  describe "edge cases" do
    test "handles empty string" do
      result = StuckDetection.analyze("")
      refute Detection.stuck?(result)
    end

    test "handles nil output" do
      result = StuckDetection.analyze(nil)
      refute Detection.stuck?(result)
    end

    test "handles unicode in output" do
      output = String.duplicate("错误: 连接失败\n", 15)
      result = StuckDetection.analyze(output)
      assert Detection.stuck?(result)
    end

    test "handles very long output" do
      output = String.duplicate("Processing line\n", 10000)
      result = StuckDetection.analyze(output)
      assert result.reason == :repetitive_output
    end

    test "handles output with no newline" do
      result = StuckDetection.analyze("Single line no newline")
      refute Detection.stuck?(result)
    end

    test "handles mixed patterns" do
      output = """
      $ npm test
      Error: Tests failed
      $ npm test
      Error: Tests failed
      $ npm test
      Error: Tests failed
      """

      result = StuckDetection.analyze(output)
      assert Detection.stuck?(result)
    end

    test "handles nil context gracefully" do
      result = StuckDetection.analyze("some output", nil)
      refute Detection.stuck?(result)
    end
  end

  describe "config overrides" do
    test "repetition_threshold can be customized" do
      output = String.duplicate("Same line\n", 3)

      result =
        StuckDetection.analyze(output, %{},
          config: %{repetition_threshold: 2, min_lines_for_analysis: 1}
        )

      assert Detection.stuck?(result)

      result =
        StuckDetection.analyze(output, %{},
          config: %{repetition_threshold: 10, min_lines_for_analysis: 1}
        )

      refute Detection.stuck?(result)
    end

    test "command_loop_threshold can be customized" do
      output = "$ cmd\n$ cmd"
      result = StuckDetection.analyze(output, %{}, config: %{command_loop_threshold: 2})
      assert Detection.stuck?(result)

      result = StuckDetection.analyze(output, %{}, config: %{command_loop_threshold: 5})
      refute Detection.stuck?(result)
    end

    test "error_loop_threshold can be customized" do
      output = "Error: Failed\nError: Failed"
      result = StuckDetection.analyze(output, %{}, config: %{error_loop_threshold: 2})
      assert Detection.stuck?(result)

      result = StuckDetection.analyze(output, %{}, config: %{error_loop_threshold: 5})
      refute Detection.stuck?(result)
    end
  end

  describe "detection details" do
    test "error_loop includes error count and unique count" do
      output = "Error: A\nError: A\nError: B\nError: A"
      result = StuckDetection.analyze(output)

      assert result.reason == :error_loop
      assert result.details.error_count == 4
      assert result.details.unique_errors == 2
    end

    test "command_loop includes command and repeat count" do
      output = "$ make test\n$ make build\n$ make test\n$ make test"
      result = StuckDetection.analyze(output)

      assert result.reason == :command_loop
      assert result.details.command == "make test"
      assert result.details.repeat_count == 3
    end

    test "repetitive_output includes line and counts" do
      output = String.duplicate("Repeated content\n", 5) <> "Unique line\n"
      result = StuckDetection.analyze(output, %{}, config: %{min_lines_for_analysis: 1})

      assert result.reason == :repetitive_output
      assert String.contains?(result.details.repeated_line, "Repeated content")
      assert result.details.repeat_count == 5
    end

    test "no_progress includes timing information" do
      last_activity = DateTime.add(DateTime.utc_now(), -350, :second)
      result = StuckDetection.analyze("output", %{last_activity: last_activity})

      assert result.reason == :no_progress
      assert result.details.elapsed_ms >= 300_000
      assert result.details.threshold_ms == 300_000
    end

    test "output_stall includes rate information" do
      history = String.duplicate("x", 10000)
      output = "y"
      result = StuckDetection.analyze(output, %{history: history, time_diff_s: 60})

      assert result.reason == :output_stall
      assert is_integer(result.details.current_rate_bps)
      assert is_integer(result.details.previous_rate_bps)
      assert result.details.rate_ratio < 0.1
    end
  end
end
