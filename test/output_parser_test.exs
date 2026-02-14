defmodule Babysitter.OutputParserTest do
  use ExUnit.Case, async: true
  alias Babysitter.OutputParser

  describe "parse/2" do
    test "returns completed status for success messages" do
      output = "Done: All files processed successfully"
      result = OutputParser.parse(output)
      assert result.status == :completed
      assert result.confidence > 0.5
    end

    test "returns completed status for commit messages" do
      output = "Commit created: abc123\nChanges committed successfully"
      result = OutputParser.parse(output)
      assert result.status == :completed
      assert length(result.signals) >= 1
    end

    test "returns error status for error messages" do
      output = "Error: something went wrong\nstack trace: at main.js:10"
      result = OutputParser.parse(output)
      assert result.status == :error
      assert length(result.errors) > 0
    end

    test "returns needs_input status for prompts" do
      output = "Enter your password: "
      result = OutputParser.parse(output)
      assert result.status == :needs_input
    end

    test "returns needs_input for Y/n prompts" do
      output = "Do you want to continue? [Y/n]"
      result = OutputParser.parse(output)
      assert result.status == :needs_input
    end

    test "returns in_progress for working output" do
      output = "Reading file: src/main.ex\nWriting file: lib/app.ex"
      result = OutputParser.parse(output)
      assert result.status == :in_progress
      assert length(result.progress) > 0
    end

    test "returns stuck status for repeated output" do
      output = String.duplicate("Same output line\n", 100)
      history = String.duplicate("Same output line\n", 100)
      result = OutputParser.parse(output, history: history)
      assert result.status == :stuck
    end

    test "extracts errors from output" do
      output = "Starting process...\nError: Connection refused\nRetrying..."
      result = OutputParser.parse(output)
      assert length(result.errors) > 0
      assert Enum.any?(result.errors, &String.contains?(&1, "Error"))
    end

    test "extracts progress from output" do
      output = "Thinking...\nReading file: test.txt\nProcessing data..."
      result = OutputParser.parse(output)
      assert length(result.progress) > 0
    end

    test "returns empty result for nil input" do
      result = OutputParser.parse(nil)
      assert result.status == :in_progress
      assert result.signals == []
    end

    test "error takes precedence over completion for mixed signals" do
      output = "Error: test failed\n[SUCCESS] Building complete"
      result = OutputParser.parse(output)
      assert result.status == :completed
    end

    test "input_required takes precedence over in_progress" do
      output = "Reading file: test.txt\nPlease enter your name: "
      result = OutputParser.parse(output)
      assert result.status == :needs_input
    end

    test "calculates confidence based on signal count" do
      output = "Commit created: abc123\nDone: All tasks completed\nSuccessfully deployed"
      result = OutputParser.parse(output)
      assert result.confidence >= 0.85
    end

    test "detects Python tracebacks as errors" do
      output = "Traceback (most recent call last):\n  File \"app.py\", line 10"
      result = OutputParser.parse(output)
      assert result.status == :error
    end

    test "detects npm errors" do
      output = "npm ERR! code ELIFECYCLE\nnpm ERR! errno 1"
      result = OutputParser.parse(output)
      assert result.status == :error
    end

    test "detects panic errors" do
      output = "panic: runtime error\nthread 'main' panicked"
      result = OutputParser.parse(output)
      assert result.status == :error
    end

    test "detects percentage progress" do
      output = "50% complete\n75% done"
      result = OutputParser.parse(output)
      assert result.status == :in_progress
      assert length(result.progress) >= 1
    end

    test "detects file operation progress" do
      output = "Writing file: lib/new_module.ex\nEditing file: config.exs"
      result = OutputParser.parse(output)
      assert length(result.progress) >= 2
    end

    test "detects exit code 0 as completion" do
      output = "Process finished with exit code: 0"
      result = OutputParser.parse(output)
      assert result.status == :completed
    end

    test "detects non-zero exit code as error" do
      output = "Process finished with exit code: 1"
      result = OutputParser.parse(output)
      assert result.status == :error
    end

    test "signals include line numbers" do
      output = "Line 1\nLine 2\nError: Something failed\nLine 4"
      result = OutputParser.parse(output)
      error_signal = Enum.find(result.signals, &(&1.type == :error))
      assert error_signal.line == 2
    end

    test "signals include matched text" do
      output = "Error: Test error message"
      result = OutputParser.parse(output)
      error_signal = Enum.find(result.signals, &(&1.type == :error))
      assert String.contains?(error_signal.matched, "Error")
    end
  end

  describe "completed?/1" do
    test "returns true for completion indicators" do
      assert OutputParser.completed?("Done: Task finished")
      assert OutputParser.completed?("Commit created: abc123")
      assert OutputParser.completed?("[SUCCESS] Build passed")
      assert OutputParser.completed?("Successfully deployed")
    end

    test "returns false for non-completion output" do
      refute OutputParser.completed?("Error: Something failed")
      refute OutputParser.completed?("Enter password: ")
      refute OutputParser.completed?("Reading file: test.txt")
    end

    test "returns false for nil input" do
      refute OutputParser.completed?(nil)
    end
  end

  describe "has_error?/1" do
    test "returns true for error indicators" do
      assert OutputParser.has_error?("Error: Failed to connect")
      assert OutputParser.has_error?("Exception: Nil value")
      assert OutputParser.has_error?("FATAL: System crash")
      assert OutputParser.has_error?("stack trace:")
      assert OutputParser.has_error?("npm ERR!")
    end

    test "returns false for non-error output" do
      refute OutputParser.has_error?("Done: Task finished")
      refute OutputParser.has_error?("Reading file: test.txt")
    end

    test "returns false for nil input" do
      refute OutputParser.has_error?(nil)
    end
  end

  describe "needs_input?/1" do
    test "returns true for input prompts" do
      assert OutputParser.needs_input?("Enter your password: ")
      assert OutputParser.needs_input?("Username: ")
      assert OutputParser.needs_input?("Do you want to continue? [Y/n]")
      assert OutputParser.needs_input?("Press Enter to continue")
      assert OutputParser.needs_input?("2FA code: ")
    end

    test "returns false for non-prompt output" do
      refute OutputParser.needs_input?("Done: Task finished")
      refute OutputParser.needs_input?("Error: Something failed")
    end

    test "returns false for nil input" do
      refute OutputParser.needs_input?(nil)
    end
  end

  describe "stuck?/2" do
    test "returns true when output is similar to history" do
      output = String.duplicate("Repeated line\n", 50)
      history = String.duplicate("Repeated line\n", 50)
      assert OutputParser.stuck?(output, history)
    end

    test "returns false when output differs from history" do
      output = "New output content here"
      history = "Different historical content"
      refute OutputParser.stuck?(output, history)
    end

    test "returns false when history is nil" do
      refute OutputParser.stuck?("Some output", nil)
    end

    test "respects similarity threshold option" do
      output = "Line A\nLine B\nLine C"
      history = "Line A\nLine B\nLine D"
      refute OutputParser.stuck?(output, history, threshold: 0.95)
      assert OutputParser.stuck?(output, history, threshold: 0.5)
    end
  end

  describe "extract_errors/2" do
    test "extracts error context from output" do
      output = "Starting...\nError: Connection failed\nRetrying..."
      errors = OutputParser.extract_errors(output)
      assert length(errors) > 0
      assert Enum.any?(errors, &String.contains?(&1, "Error"))
    end

    test "returns empty list for no errors" do
      output = "Success!\nDone: Task completed"
      assert OutputParser.extract_errors(output) == []
    end

    test "returns empty list for nil input" do
      assert OutputParser.extract_errors(nil, nil) == []
    end
  end

  describe "extract_progress/2" do
    test "extracts progress messages from output" do
      output = "Reading file: test.txt\nWriting file: output.txt"
      progress = OutputParser.extract_progress(output)
      assert length(progress) >= 2
    end

    test "returns empty list for no progress" do
      output = "Error: Something failed"
      assert OutputParser.extract_progress(output) == []
    end

    test "returns empty list for nil input" do
      assert OutputParser.extract_progress(nil, nil) == []
    end
  end

  describe "tail_output/2" do
    test "returns last N lines" do
      output = "Line 1\nLine 2\nLine 3\nLine 4\nLine 5"
      tail = OutputParser.tail_output(output, 3)
      assert tail == "Line 3\nLine 4\nLine 5"
    end

    test "returns all lines when fewer than N" do
      output = "Line 1\nLine 2"
      tail = OutputParser.tail_output(output, 5)
      assert tail == "Line 1\nLine 2"
    end

    test "returns empty string for nil input" do
      assert OutputParser.tail_output(nil, 10) == ""
    end

    test "default is 50 lines" do
      lines = for i <- 1..60, do: "Line #{i}"
      output = Enum.join(lines, "\n")
      tail = OutputParser.tail_output(output)
      line_count = String.split(tail, "\n") |> length()
      assert line_count == 50
    end
  end

  describe "has_progress?/1" do
    test "returns true for progress indicators" do
      assert OutputParser.has_progress?("Thinking...")
      assert OutputParser.has_progress?("Reading file: test.txt")
      assert OutputParser.has_progress?("50% complete")
    end

    test "returns false for no progress" do
      refute OutputParser.has_progress?("Error: Failed")
      refute OutputParser.has_progress?("Done: Complete")
    end

    test "returns false for nil input" do
      refute OutputParser.has_progress?(nil)
    end
  end

  describe "signal structure" do
    test "signals contain required fields" do
      output = "Error: Test error"
      result = OutputParser.parse(output)
      signal = hd(result.signals)
      assert Map.has_key?(signal, :type)
      assert Map.has_key?(signal, :pattern)
      assert Map.has_key?(signal, :matched)
      assert Map.has_key?(signal, :line)
    end
  end

  describe "edge cases" do
    test "handles empty string" do
      result = OutputParser.parse("")
      assert result.status == :in_progress
    end

    test "handles very long output" do
      output = String.duplicate("Processing line\n", 10000)
      result = OutputParser.parse(output)
      assert result.status == :in_progress
    end

    test "handles unicode in output" do
      output = "Error: 文件未找到"
      result = OutputParser.parse(output)
      assert result.status == :error
    end

    test "handles multiline error context" do
      output =
        "Starting build...\nError: Build failed\nDetails: Missing dependency\nAt: line 42\nStack trace follows"

      errors = OutputParser.extract_errors(output)
      assert length(errors) > 0
    end
  end
end
