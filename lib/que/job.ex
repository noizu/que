defmodule Que.Job do
  defstruct  [:id, :node, :priority, :arguments, :worker, :status, :ref, :pid, :created_at, :updated_at]
  ## Note: Update Que.Persistence.Mnesia after changing these values


  @moduledoc """
  Module to manage a Job's state and execute the worker's callbacks.

  Defines a `Que.Job` struct an keeps track of the Job's worker, arguments,
  status and more. Meant for internal usage, so you shouldn't use this
  unless you absolutely know what you're doing.
  """


  @statuses [:queued, :started, :failed, :completed]
  @typedoc  "One of the atoms in `#{inspect(@statuses)}`"
  @type     status :: atom

  @typedoc  "A `Que.Job` struct"
  @type     t :: %Que.Job{}

  @doc """
  Returns a new Job struct with defaults
  """
  @spec new(worker :: Que.Worker.t, args :: list, priority :: :pri0 | :pri1 | :pri2 | :pri3, node :: atom) :: Que.Job.t
  def new(worker, args \\ nil, priority \\ :pri0, node \\ nil) do
    %Que.Job{
      node: node || node(),
      priority: priority,
      status:    :queued,
      worker:    worker,
      arguments: args
    }
  end


  @doc """
  Returns a new pri0 Job struct with defaults
  """
  @spec pri0(worker :: Que.Worker.t, args :: list) :: Que.Job.t
  def pri0(worker, args \\ nil), do: new(worker, args, :pri0)

  @doc """
  Returns a new pri0 Job struct with defaults
  """
  @spec pri1(worker :: Que.Worker.t, args :: list) :: Que.Job.t
  def pri1(worker, args \\ nil), do: new(worker, args, :pri1)

  @doc """
  Returns a new pri0 Job struct with defaults
  """
  @spec pri2(worker :: Que.Worker.t, args :: list) :: Que.Job.t
  def pri2(worker, args \\ nil), do: new(worker, args, :pri2)

  @doc """
  Returns a new pri0 Job struct with defaults
  """
  @spec pri3(worker :: Que.Worker.t, args :: list) :: Que.Job.t
  def pri3(worker, args \\ nil), do: new(worker, args, :pri3)


  @doc """
  Update the Job status to one of the predefined values in `@statuses`
  """
  @spec set_status(job :: Que.Job.t, status :: status) :: Que.Job.t
  def set_status(job, status) when status in @statuses do
    %{ job | status: status }
  end




  @doc """
  Updates the Job struct with new status and spawns & monitors a new Task
  under the TaskSupervisor which executes the perform method with supplied
  arguments
  """
  @spec perform(job :: Que.Job.t) :: Que.Job.t
  def perform(job) do
    Que.Helpers.log("Starting #{job}")

    {:ok, pid} =
      Que.Helpers.do_task(fn ->
        job.worker.on_setup(job)
        job.worker.perform(job.arguments)
      end)

    %{ job | status: :started, pid: pid, ref: Process.monitor(pid) }
  end




  @doc """
  Handles Job Success, Calls appropriate worker method and updates the job
  status to :completed
  """
  @spec handle_success(job :: Que.Job.t) :: Que.Job.t
  def handle_success(job) do
    Que.Helpers.log("Completed #{job}")

    Que.Helpers.do_task(fn ->
      job.worker.on_success(job.arguments)
      job.worker.on_teardown(job)
    end)

    %{ job | status: :completed, pid: nil, ref: nil }
  end




  @doc """
  Handles Job Failure, Calls appropriate worker method and updates the job
  status to :failed
  """
  @spec handle_failure(job :: Que.Job.t, error :: term) :: Que.Job.t
  def handle_failure(job, error) do
    Que.Helpers.log("Failed #{job}")

    Que.Helpers.do_task(fn ->
      job.worker.on_failure(job.arguments, error)
      job.worker.on_teardown(job)
    end)

    %{ job | status: :failed, pid: nil, ref: nil }
  end
end




## Implementing the String.Chars protocol for Que.Job structs

defimpl String.Chars, for: Que.Job do
  def to_string(job) do
    "Job # #{inspect job.id} with #{ExUtils.Module.name(job.worker)}"
  end
end

