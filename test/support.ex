## Namespace all test related modules under Que.Test.Meta
## ======================================================

defmodule Que.Test.Meta do
  require Logger


  # Test workers for handling Jobs
  # ==============================

  defmodule TestWorker do
    use Que.Worker

    def perform(args), do: Logger.debug("#{__MODULE__} - perform: #{inspect(args)}")
  end

  defmodule TestShardWorker do
    use Que.ShardWorker, shards: 10
    def perform(args) do
      Process.sleep(20)
      Logger.debug("#{__MODULE__} - perform: #{inspect(args)}")
    end
  end

  defmodule ConcurrentWorker do
    use Que.Worker, concurrency: 4

    def perform(args), do: Logger.debug("#{__MODULE__} - perform: #{inspect(args)}")
  end


  defmodule SuccessWorker do
    use Que.Worker

    def perform(args),    do: Logger.debug("#{__MODULE__} - perform: #{inspect(args)}")
    def on_success(args), do: Logger.debug("#{__MODULE__} - success: #{inspect(args)}")
  end


  defmodule FailureWorker do
    use Que.Worker

    def perform(args) do
      Logger.debug("#{__MODULE__} - perform: #{inspect(args)}")
      raise "some error"
    end

    def on_failure(args, _err), do: Logger.debug("#{__MODULE__} - failure: #{inspect(args)}")
  end


  defmodule SleepWorker do
    use Que.Worker

    def perform(args) do
      Process.sleep(1000)
      Logger.debug("#{__MODULE__} - perform: #{inspect(args)}")
    end

    def on_success(args),       do: Logger.debug("#{__MODULE__} - success: #{inspect(args)}")
    def on_failure(args, _err), do: Logger.debug("#{__MODULE__} - failure: #{inspect(args)}")
  end


  defmodule SetupAndTeardownWorker do
    use Que.Worker

    def perform(args),     do: Logger.debug("#{__MODULE__} - perform: #{inspect(args)}")
    def on_setup(job),     do: Logger.debug("#{__MODULE__} - on_setup: #{inspect(job)}")
    def on_teardown(job),  do: Logger.debug("#{__MODULE__} - on_teardown: #{inspect(job)}")
  end




  # Helper Module for Tests
  # =======================

  defmodule Helpers do

    # Sleeps for 2ms
    def wait(ms \\ 3) do
      :timer.sleep(ms)
    end

    def wait_for_children do
      Task.Supervisor.children(Que.TaskSupervisor)
      |> Enum.map(&Process.monitor/1)
      |> Enum.each(fn ref ->
        receive do
          {:DOWN, ^ref, _, _, _} -> nil
        end
      end)
    end

    # Captures IO output
    def capture_io(fun) do
      ExUnit.CaptureIO.capture_io(fun)
    end

    # Captures logged text to IO
    def capture_log(fun) do
      ExUnit.CaptureLog.capture_log(fun)
    end

    # Captures everything
    def capture_all(fun) do
      capture_io(fn ->
        IO.puts capture_log(fn -> fun |> capture_io |> IO.puts end)
      end)
    end

  end



  # App-specific helpers
  # ====================

  defmodule Helpers.App do
    # Restarts app and resets DB
    def reset do
      stop()
      Helpers.Mnesia.reset
      start()
      :ok
    end

    def start do
      Application.start(:que)
    end

    def stop do
      Helpers.capture_log(fn ->
        Application.stop(:que)
      end)
    end
  end



  # Mnesia-specific helpers
  # =======================

  defmodule Helpers.Mnesia do
    @adapter (Application.get_env(:que, :persistence_strategy) || Que.Persistence.Mnesia)

    # Cleans up Mnesia DB
    def reset do
      @adapter.reset()
    end

    # Deletes the Mnesia DB from disk and creates a fresh one in memory
    def reset! do
      Helpers.capture_log(fn ->
        @adapter.reset!()
      end)
    end

    # Creates sample Mnesia jobs
    def create_sample_jobs do
      [
        %Que.Job{id: 1, node: node(), priority: :pri0, status: :completed, worker: TestWorker    },
        %Que.Job{id: 2, node: node(), priority: :pri0, status: :completed, worker: SuccessWorker },
        %Que.Job{id: 3, node: node(), priority: :pri0, status: :failed,    worker: FailureWorker },
        %Que.Job{id: 4, node: node(), priority: :pri0, status: :started,   worker: TestWorker    },
        %Que.Job{id: 5, node: node(), priority: :pri0, status: :queued,    worker: SuccessWorker },
        %Que.Job{id: 6, node: node(), priority: :pri0, status: :queued,    worker: FailureWorker }
      ] |> Enum.map(&@adapter.insert/1)
    end



  end

end
