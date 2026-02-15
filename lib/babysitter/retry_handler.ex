defmodule Babysitter.RetryHandler do
  @moduledoc """
  Handles retry logic with error context passed to modified prompts.

  When a stage fails and needs to be retried, this module builds
  a modified prompt that includes:
  - The error that occurred
  - The previous output (truncated if too long)
  - Guidance on what to fix
  """

  alias Babysitter.{Stage, StageContext, StageExecutor.Result, TemplateInterpolator}
  alias Babysitter.Intervention.Result, as: InterventionResult

  @default_max_output_length 2000
  @default_retry_template """
  The previous attempt encountered an issue. Please try again with this context:

  ## Error Context
  {{retry.error_message}}

  {{#if retry.validation_errors}}
  ## Validation Errors
  {{retry.validation_errors}}
  {{/if}}

  {{#if retry.previous_output}}
  ## Previous Output (last {{retry.output_length}} characters)
  ```
  {{retry.previous_output}}
  ```
  {{/if}}

  ## Original Task
  {{retry.original_prompt}}

  Please address the issues above and try again.
  """

  @spec build_retry_prompt(Stage.t(), Result.t(), keyword()) :: String.t()
  def build_retry_prompt(%Stage{} = stage, %Result{} = result, opts \\ []) do
    template = Keyword.get(opts, :template, @default_retry_template)
    max_output_length = Keyword.get(opts, :max_output_length, @default_max_output_length)
    include_output = Keyword.get(opts, :include_previous_output, true)
    context = build_retry_context(stage, result, max_output_length, include_output, opts)
    interpolate_template(template, context)
  end

  @spec build_retry_prompt_from_intervention(Stage.t(), Result.t(), InterventionResult.t(), keyword()) :: String.t()
  def build_retry_prompt_from_intervention(%Stage{} = stage, %Result{} = result, %InterventionResult{action: :retry} = intervention, opts \\ []) do
    opts = Keyword.merge(opts, intervention_context_to_opts(intervention))
    build_retry_prompt(stage, result, opts)
  end

  @spec build_retry_opts(StageContext.t(), Result.t(), keyword()) :: keyword()
  def build_retry_opts(%StageContext{} = context, %Result{} = result, opts \\ []) do
    retry_count = Keyword.get(opts, :retry_count, 1)
    retry_vars = %{
      "RETRY_COUNT" => to_string(retry_count),
      "RETRY_ERROR" => result.error || "",
      "RETRY_EXIT_CODE" => to_string(result.exit_code || 0)
    }
    retry_vars = if result.validation_errors do
      Map.put(retry_vars, "RETRY_VALIDATION_ERRORS", Enum.join(result.validation_errors, "; "))
    else
      retry_vars
    end
    base_opts = StageContext.to_execution_opts(context, opts)
    Keyword.update(base_opts, :env, [], fn existing ->
      (existing || []) ++ Map.to_list(retry_vars)
    end)
  end

  @spec should_retry?(Result.t(), keyword()) :: boolean()
  def should_retry?(%Result{status: :success}, _opts), do: false
  def should_retry?(%Result{status: status}, opts) when status in [:failure, :timeout] do
    retry_count = Keyword.get(opts, :retry_count, 0)
    max_retries = Keyword.get(opts, :max_retries, 3)
    recoverable = Keyword.get(opts, :recoverable, true)
    retry_count < max_retries and recoverable
  end
  def should_retry?(_result, _opts), do: false

  @spec record_retry(StageContext.t(), Result.t(), keyword()) :: StageContext.t()
  def record_retry(%StageContext{} = context, %Result{} = result, opts \\ []) do
    retry_count = Keyword.get(opts, :retry_count, 1)
    error_type = if result.status == :timeout, do: :timeout, else: :execution
    error_message = build_error_message(result, opts)
    context
    |> StageContext.record_error(result.stage_id, error_message, error_type)
    |> StageContext.put_variable(:retry_count, retry_count)
    |> StageContext.put_variable(:last_retry_error, error_message)
  end

  @spec format_validation_errors([String.t()]) :: String.t()
  def format_validation_errors([]), do: ""
  def format_validation_errors(errors) when is_list(errors) do
    errors |> Enum.map(fn error -> "- #{error}" end) |> Enum.join("\n")
  end
  def format_validation_errors(error) when is_binary(error), do: "- #{error}"
  def format_validation_errors(_), do: ""

  @spec truncate_output(String.t(), keyword()) :: String.t()
  def truncate_output(output, opts \\ [])
  def truncate_output(nil, _opts), do: ""
  def truncate_output(output, opts) when is_binary(output) do
    max_length = Keyword.get(opts, :max_length, @default_max_output_length)
    if String.length(output) <= max_length do
      output
    else
      "... " <> String.slice(output, -max_length + 4, max_length - 4)
    end
  end
  def truncate_output(output, opts) when is_list(output) do
    output |> Enum.join("\n") |> truncate_output(opts)
  end
  def truncate_output(_, _opts), do: ""

  defp build_retry_context(stage, result, max_output_length, include_output, opts) do
    retry_count = Keyword.get(opts, :retry_count, 1)
    %{
      error_message: build_error_message(result, opts),
      validation_errors: format_validation_errors(result.validation_errors),
      previous_output: if(include_output, do: truncate_output(Keyword.get(opts, :previous_output, result.output), max_length: max_output_length), else: nil),
      output_length: min(String.length(result.output || ""), max_output_length),
      original_prompt: stage.prompt || "",
      retry_count: retry_count,
      exit_code: Keyword.get(opts, :exit_code, result.exit_code)
    }
  end

  defp build_error_message(%Result{status: :timeout}, opts) do
    Keyword.get_lazy(opts, :error_message, fn -> "Execution timed out before completing" end)
  end
  defp build_error_message(%Result{error: error}, opts) when is_binary(error) and error != "" do
    Keyword.get_lazy(opts, :error_message, fn -> error end)
  end
  defp build_error_message(%Result{exit_code: code}, opts) when is_integer(code) and code > 0 do
    Keyword.get_lazy(opts, :error_message, fn -> "Command exited with code #{code}" end)
  end
  defp build_error_message(%Result{validation_errors: errors}, opts) when is_list(errors) and errors != [] do
    Keyword.get_lazy(opts, :error_message, fn -> "Validation failed: #{Enum.join(errors, ", ")}" end)
  end
  defp build_error_message(_result, opts), do: Keyword.get(opts, :error_message, "An unexpected error occurred")

  defp interpolate_template(template, context) do
    template |> handle_conditionals(context) |> TemplateInterpolator.interpolate(%{retry: context}, missing: :empty)
  end

  defp handle_conditionals(template, context) do
    template |> handle_conditional("validation_errors", context.validation_errors) |> handle_conditional("previous_output", context.previous_output)
  end

  defp handle_conditional(template, field, nil) do
    Regex.replace(~r/\{\{#if retry\.#{field}\}\}.*?\{\{\/if\}\}/s, template, "")
  end
  defp handle_conditional(template, field, "") do
    Regex.replace(~r/\{\{#if retry\.#{field}\}\}.*?\{\{\/if\}\}/s, template, "")
  end
  defp handle_conditional(template, field, value) when is_list(value) and value == [] do
    Regex.replace(~r/\{\{#if retry\.#{field}\}\}.*?\{\{\/if\}\}/s, template, "")
  end
  defp handle_conditional(template, _field, _value), do: template

  defp intervention_context_to_opts(%InterventionResult{context: nil, reason: reason}) do
    [error_message: reason]
  end
  defp intervention_context_to_opts(%InterventionResult{context: context, reason: reason}) do
    opts = [error_message: reason]
    opts = if Map.has_key?(context, :error_output), do: Keyword.put(opts, :previous_output, context.error_output), else: opts
    opts = if Map.has_key?(context, :validation_type), do: Keyword.put(opts, :validation_type, context.validation_type), else: opts
    if Map.has_key?(context, :exit_code), do: Keyword.put(opts, :exit_code, context.exit_code), else: opts
  end
end
