defmodule Babysitter.PRTrigger do
  @moduledoc """
  Execute PR creation based on triggers with context-aware template generation.

  Supports three trigger types:
  - `:workflow_complete` - After entire workflow completes
  - `:stage_complete` - After each stage completes successfully
  - `:manual` - Manual PR creation triggered by user

  ## Configuration

  Configure in ~/.config/babysitter/config.yaml:

      git:
        pr_strategy:
          trigger: workflow_complete
          title_template: "{{issue.id}}: {{issue.title}}"
          body_template: "## Summary\n{{stage.summary}}\n\n## Completed\n{{issue.done}}"
          labels: ["automated"]
          reviewers: []
          base: main
          draft: false

  ## Options

  - `:dry_run` - Preview PR without executing (default: false)
  - `:title` - Override PR title
  - `:body` - Override PR body
  - `:labels` - Override PR labels
  - `:reviewers` - Override PR reviewers
  - `:base` - Override base branch
  - `:head` - Override head branch (default: current branch)
  - `:draft` - Override draft flag
  - `:issue` - Issue map for template context
  - `:stage` - Stage map for template context

  ## Examples

      PRTrigger.execute(:workflow_complete, issue, stage: stage)
      PRTrigger.on_workflow_complete(issue, stage: stage, dry_run: true)
      PRTrigger.preview(:manual, issue, stage: stage)
  """

  alias Babysitter.{Config, PR, Git, TemplateInterpolator}

  @type trigger :: :workflow_complete | :stage_complete | :manual
  @type error :: {:error, String.t()}

  @doc """
  Execute PR creation based on trigger type.

  ## Parameters

  - `trigger` - The trigger type atom
  - `issue` - Issue map with id, title, last_handoff, etc.
  - `opts` - Additional options and context:
    - `:stage` - Stage map with id, name, summary
    - `:dry_run` - Preview without executing
    - `:title` - Override title template
    - `:body` - Override body template
    - `:labels` - Override labels
    - `:reviewers` - Override reviewers
    - `:base` - Override base branch
    - `:head` - Override head branch
    - `:draft` - Override draft flag

  ## Examples

      iex> PRTrigger.execute(:workflow_complete, %{id: "td-123", title: "Feature"}, stage: %{summary: "Done"})
      {:ok, %{url: "https://github.com/...", number: 42}}
  """
  @spec execute(trigger(), map(), keyword()) :: {:ok, map()} | error()
  def execute(trigger, issue, opts \\ []) do
    dry_run = Keyword.get(opts, :dry_run, false)

    config_trigger = Config.git_pr_trigger()

    if config_trigger == trigger or trigger == :manual do
      do_execute(trigger, issue, opts, dry_run)
    else
      {:error, "PR trigger #{config_trigger} does not match #{trigger}"}
    end
  end

  defp do_execute(trigger, issue, opts, true) do
    title = build_title(issue, opts)
    body = build_body(issue, opts)
    {:ok, %{title: title, body: body, dry_run: true, trigger: trigger}}
  end

  defp do_execute(_trigger, issue, opts, false) do
    title = build_title(issue, opts)
    body = build_body(issue, opts)
    labels = Keyword.get(opts, :labels, Config.git_pr_labels())
    reviewers = Keyword.get(opts, :reviewers, Config.git_pr_reviewers())
    base = Keyword.get(opts, :base, Config.git_pr_base())
    head = Keyword.get(opts, :head, Git.current_branch())
    draft = Keyword.get(opts, :draft, Config.git_pr_draft?())

    template_context = build_template_context(issue, opts)

    result =
      PR.create(
        title: title,
        body: body,
        base: base,
        head: head,
        draft: draft,
        issue: issue,
        template_context: template_context
      )

    case result do
      {:ok, pr_data} = success ->
        label_result =
          if labels != [], do: PR.add_labels(pr: pr_data[:number], labels: labels), else: :ok

        reviewer_result =
          if reviewers != [],
            do: PR.add_reviewers(pr: pr_data[:number], reviewers: reviewers),
            else: :ok

        final_result =
          case {label_result, reviewer_result} do
            {:ok, :ok} ->
              success

            {{:error, _}, :ok} ->
              {:error, "PR created but failed to add labels"}

            {:ok, {:error, _}} ->
              {:error, "PR created but failed to add reviewers"}

            {{:error, _}, {:error, _}} ->
              {:error, "PR created but failed to add labels and reviewers"}
          end

        final_result

      error ->
        error
    end
  end

  defp build_title(issue, opts) do
    case Keyword.get(opts, :title) do
      nil ->
        template = Keyword.get(opts, :title_template, Config.git_pr_title_template())
        template_context = build_template_context(issue, opts)
        TemplateInterpolator.interpolate(template, template_context)

      title ->
        title
    end
  end

  defp build_body(issue, opts) do
    case Keyword.get(opts, :body) do
      nil ->
        template = Keyword.get(opts, :body_template, Config.git_pr_body_template())
        template_context = build_template_context(issue, opts)
        TemplateInterpolator.interpolate(template, template_context)

      body ->
        body
    end
  end

  defp build_template_context(issue, opts) do
    stage = Keyword.get(opts, :stage, %{})

    %{
      "issue" => issue,
      "stage" => stage,
      "branch" => Git.current_branch() |> Kernel.||("main")
    }
  end

  @doc """
  Execute PR creation with a custom template.

  ## Examples

      iex> PRTrigger.execute_with_template("Issue {{issue.id}}", issue, stage: stage)
      {:ok, %{url: "https://github.com/...", number: 42}}
  """
  @spec execute_with_template(String.t(), map(), keyword()) :: {:ok, map()} | error()
  def execute_with_template(title_template, issue, opts \\ []) do
    execute(:manual, issue, Keyword.put(opts, :title_template, title_template))
  end

  @doc """
  Preview PR without creating it.

  ## Examples

      iex> PRTrigger.preview(:workflow_complete, issue, stage: stage)
      {:ok, %{title: "...", body: "...", dry_run: true}}
  """
  @spec preview(trigger(), map(), keyword()) :: {:ok, map()}
  def preview(trigger, issue, opts \\ []) do
    execute(trigger, issue, Keyword.put(opts, :dry_run, true))
  end

  @doc """
  Convenience function for workflow_complete trigger.

  ## Examples

      iex> PRTrigger.on_workflow_complete(issue, stage: stage)
      {:ok, %{url: "https://github.com/...", number: 42}}
  """
  @spec on_workflow_complete(map(), keyword()) :: {:ok, map()} | error()
  def on_workflow_complete(issue, opts \\ []) do
    execute(:workflow_complete, issue, opts)
  end

  @doc """
  Convenience function for stage_complete trigger.

  ## Examples

      iex> PRTrigger.on_stage_complete(issue, stage: stage)
      {:ok, %{url: "https://github.com/...", number: 42}}
  """
  @spec on_stage_complete(map(), keyword()) :: {:ok, map()} | error()
  def on_stage_complete(issue, opts \\ []) do
    execute(:stage_complete, issue, opts)
  end

  @doc """
  Convenience function for manual trigger.

  ## Examples

      iex> PRTrigger.on_manual(issue, stage: stage)
      {:ok, %{url: "https://github.com/...", number: 42}}
  """
  @spec on_manual(map(), keyword()) :: {:ok, map()} | error()
  def on_manual(issue, opts \\ []) do
    execute(:manual, issue, opts)
  end

  @doc """
  Check if a PR should be created based on conditions.

  ## Examples

      iex> PRTrigger.should_trigger?(:workflow_complete, has_branch: true)
      true
  """
  @spec should_trigger?(trigger(), keyword()) :: boolean()
  def should_trigger?(trigger, opts \\ []) do
    has_branch = Keyword.get(opts, :has_branch, match?({:ok, _}, Git.current_branch()))

    case trigger do
      :workflow_complete -> has_branch
      :stage_complete -> has_branch
      :manual -> has_branch
    end
  end
end
