defmodule Babysitter.Validation do
  @moduledoc """
  Defines a validation rule for a stage.

  Validations check the output/result of a stage execution
  to determine if it was successful.
  """

  @derive Jason.Encoder
  @type validation_type ::
          :output_contains
          | :output_matches
          | :exit_code
          | :output_equals
          | :custom

  @type t :: %__MODULE__{
          type: validation_type(),
          pattern: String.t() | Regex.t() | non_neg_integer() | function(),
          negate: boolean(),
          error_message: String.t() | nil
        }

  @enforce_keys [:type, :pattern]
  defstruct [
    :type,
    :pattern,
    negate: false,
    error_message: nil
  ]

  @doc """
  Create a validation that checks if output contains a string.
  """
  @spec output_contains(String.t(), keyword()) :: t()
  def output_contains(pattern, opts \\ []) do
    %__MODULE__{
      type: :output_contains,
      pattern: pattern,
      negate: Keyword.get(opts, :negate, false),
      error_message: Keyword.get(opts, :error_message)
    }
  end

  @doc """
  Create a validation that matches output against a regex.
  """
  @spec output_matches(String.t() | Regex.t(), keyword()) :: t()
  def output_matches(pattern, opts \\ []) do
    pattern = if is_binary(pattern), do: Regex.compile!(pattern), else: pattern

    %__MODULE__{
      type: :output_matches,
      pattern: pattern,
      negate: Keyword.get(opts, :negate, false),
      error_message: Keyword.get(opts, :error_message)
    }
  end

  @doc """
  Create a validation that checks the exit code.
  """
  @spec exit_code(non_neg_integer() | [non_neg_integer()], keyword()) :: t()
  def exit_code(code, opts \\ []) do
    %__MODULE__{
      type: :exit_code,
      pattern: code,
      negate: Keyword.get(opts, :negate, false),
      error_message: Keyword.get(opts, :error_message)
    }
  end

  @doc """
  Create a validation that checks if output equals a string.
  """
  @spec output_equals(String.t(), keyword()) :: t()
  def output_equals(expected, opts \\ []) do
    %__MODULE__{
      type: :output_equals,
      pattern: expected,
      negate: Keyword.get(opts, :negate, false),
      error_message: Keyword.get(opts, :error_message)
    }
  end

  @doc """
  Run the validation against output and exit code.
  """
  @spec run(t(), String.t(), non_neg_integer()) :: :ok | {:error, String.t()}
  def run(%__MODULE__{} = validation, output, exit_code) do
    result = do_validate(validation, output, exit_code)

    if validation.negate do
      case result do
        :ok -> error(validation, "negated validation passed")
        {:error, _} -> :ok
      end
    else
      result
    end
  end

  defp do_validate(%__MODULE__{type: :output_contains, pattern: pattern} = v, output, _exit_code) do
    if String.contains?(output, pattern) do
      :ok
    else
      error(v, "output does not contain '#{pattern}'")
    end
  end

  defp do_validate(%__MODULE__{type: :output_matches, pattern: regex} = v, output, _exit_code) do
    if Regex.match?(regex, output) do
      :ok
    else
      error(v, "output does not match pattern")
    end
  end

  defp do_validate(%__MODULE__{type: :exit_code, pattern: expected} = v, _output, exit_code) do
    codes = if is_list(expected), do: expected, else: [expected]

    if exit_code in codes do
      :ok
    else
      error(v, "exit code #{exit_code} not in expected #{inspect(codes)}")
    end
  end

  defp do_validate(%__MODULE__{type: :output_equals, pattern: expected} = v, output, _exit_code) do
    if output == expected do
      :ok
    else
      error(v, "output does not equal expected value")
    end
  end

  defp do_validate(%__MODULE__{type: :custom, pattern: func}, output, exit_code)
       when is_function(func, 2) do
    func.(output, exit_code)
  end

  defp error(validation, message) do
    {:error, validation.error_message || message}
  end
end
