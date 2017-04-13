defmodule Que.Queue do
  defstruct [:worker, :queued, :running]


  @doc """
  Returns a new processable Queue with defaults
  """
  def new(worker, jobs \\ []) do
    %Que.Queue{
      worker:  worker,
      queued:  jobs,
      running: []
    }
  end



  @doc """
  Processes the Queue and runs pending jobs
  """
  def process(%Que.Queue{running: running, worker: worker} = q) do
    Que.Worker.validate!(worker)

    if (length(running) < worker.concurrency) do
      case pop(q) do
        {q, nil} ->
          q

        {q, job} ->
          job =
            job
            |> Que.Job.perform
            |> Que.Persistence.update

          %{ q | running: running ++ [job] }
      end

    else
      q
    end
  end



  @doc """
  Pushes one or more Jobs to the `queued` list
  """
  def push(%Que.Queue{queued: queued} = q, jobs) when is_list(jobs) do
    %{ q | queued: queued ++ jobs }
  end

  def push(queue, job) do
    push(queue, [job])
  end



  @doc """
  Pops the next Job in queue and returns a queue and Job tuple
  """
  def pop(%Que.Queue{queued: [ job | rest ]} = q) do
    { %{ q | queued: rest }, job }
  end

  def pop(%Que.Queue{queued: []} = q) do
    { q, nil }
  end



  @doc """
  Finds the Job in Queue by the specified key name and value.

  If no key is specified, it's assumed to be an `:id`. If the
  specified key is a :ref, it only searches in the `:running`
  list.
  """
  def find(queue, key \\ :id, value)

  def find(%Que.Queue{ running: running }, :ref, value) do
    Enum.find(running, &(Map.get(&1, :ref) == value))
  end

  def find(%Que.Queue{ running: running, queued: queued }, key, value) do
    Enum.find(queued,  &(Map.get(&1, key) == value)) ||
    Enum.find(running, &(Map.get(&1, key) == value))
  end



  @doc """
  Finds a Job in the Queue by the given Job's id, replaces it and
  returns an updated Queue
  """
  def update(%Que.Queue{} = q, %Que.Job{} = job) do
    queued_index = Enum.find_index(q.queued, &(&1.id == job.id))

    if queued_index do
      queued = List.replace_at(q.queued, queued_index, job)
      %{ q | queued: queued }

    else
      running_index = Enum.find_index(q.running, &(&1.id == job.id))

      if running_index do
        running = List.replace_at(q.running, running_index, job)
        %{ q | running: running }

      else
        raise Que.Error.JobNotFound, "Job not found in Queue"
      end
    end
  end



  @doc """
  Removes the specified Job from `running`
  """
  def remove(%Que.Queue{} = q, %Que.Job{} = job) do
    index = Enum.find_index(q.running, &(&1.id == job.id))

    if index do
      %{ q | running: List.delete_at(q.running, index) }
    else
      raise Que.Error.JobNotFound, "Job not found in Queue"
    end
  end

end
