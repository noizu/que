

# Fake Space to simplify DB Layout
defmodule Que.Persistence.Mnesia.DB.AUIN do
  use Memento.Table,
      attributes: [:id, :counter],
      index: [],
      type: :ordered_set,
      autoincrement: false
end

defmodule Que.Persistence.DirtyMnesia.DB do
  @moduledoc false

  # TODO:
  # Convert this to a Memento.Collection if we add
  # more Mnesia tables




  # Memento Table Definition
  # ========================



  defmodule Jobs do
    require Memento.Error
    use Memento.Table,
        attributes: [:id, :node, :priority, :arguments, :worker, :status, :ref, :pid, :created_at, :updated_at],
        index: [:node, :priority, :worker, :status],
        type: :ordered_set,
        autoincrement: true



    @moduledoc false

    # Avoid requiring new table to allow switching between modes more easily for experimentation.
    @store     Que.Persistence.Mnesia.DB.Jobs

    @multi_tenant (Application.get_env(:que, :multi_tenant) || false)
    @auto_inc Que.Persistence.Mnesia.DB.AUIN

    # Persistence Implementation
    # --------------------------


    @doc "Finds all Jobs"
    def all_jobs do
      run_query([])
    end



    @doc "Find all Jobs for a worker"
    def all_jobs(name) do
      if @multi_tenant do
        run_query(
          {:and,
            {:==, :node, node()},
            {:==, :worker, name}
          }
        )
      else
        run_query(
          {:==, :worker, name}
        )
      end


    end



    @doc "Find Completed Jobs"
    def completed_jobs do
      if @multi_tenant do
        run_query(
          {:and,
            {:==, :node, node()},
            {:==, :status, :completed}
          }
        )
      else
        run_query(
          {:==, :status, :completed}
        )
      end
    end



    @doc "Find Completed Jobs for worker"
    def completed_jobs(name) do
      if @multi_tenant do
        run_query(
          {:and,
            {:==, :node, node()},
            {:and,
              {:==, :worker, name},
              {:==, :status, :completed}
            }

          }
        )
      else
        run_query(
          {:and,
            {:==, :worker, name},
            {:==, :status, :completed}
          }
        )
      end
    end



    @doc "Find Incomplete Jobs"
    def incomplete_jobs do
      if @multi_tenant do
        run_query(
          {:and,
            {:==, :node, node()},
            {:or,
              {:==, :status, :queued},
              {:==, :status, :started}
            }
          }
        )
      else
        run_query(
          {:or,
            {:==, :status, :queued},
            {:==, :status, :started}
          }
        )
      end
    end



    @doc "Find Incomplete Jobs for worker"
    def incomplete_jobs(name) do
      if @multi_tenant do
        run_query(
          {:and,
            {:==, :node, node()},
            {:and,
              {:==, :worker, name},
              {:or,
                {:==, :status, :queued},
                {:==, :status, :started}
              }
            }
          }
        )
      else
        run_query(
          {:and,
            {:==, :worker, name},
            {:or,
              {:==, :status, :queued},
              {:==, :status, :started}
            }
          }
        )
      end
    end



    @doc "Find Failed Jobs"
    def failed_jobs do
      if @multi_tenant do
        run_query(
          {:and,
            {:==, :node, node()},
            {:==, :status, :failed}
          }
        )
      else
        run_query(
          {:==, :status, :failed}
        )
      end


    end



    @doc "Find Failed Jobs for worker"
    def failed_jobs(name) do
      if @multi_tenant do
        run_query(
          {:and,
            {:==, :node, node()},
            {:and,
              {:==, :worker, name},
              {:==, :status, :failed}
            }
          }
        )
      else
        run_query(
          {:and,
            {:==, :worker, name},
            {:==, :status, :failed}
          }
        )
      end


    end



    @doc "Finds a Job in the DB"
    def find_job(job) do
      #Memento.transaction! fn ->
      job
      |> normalize_id
      |> read
      |> to_que_job
      #end
    end



    @doc "Inserts a new Que.Job in to DB"
    def create_job(job) do
      job
      |> Map.put(:created_at, NaiveDateTime.utc_now)
      |> update_job
    end



    @doc "Updates existing Que.Job in DB"
    def update_job(job) do
      #Memento.transaction! fn ->
      job
      |> Map.put(:updated_at, NaiveDateTime.utc_now)
      |> to_db_job
      |> write
      |> to_que_job
      #end
    end



    @doc "Deletes a Que.Job from the DB"
    def delete_job(job) do
      #Memento.transaction! fn ->
      job
      |> normalize_id
      |> delete
      #end
    end




    ## PRIVATE METHODS

    # Execute a Memento Query
    defp run_dirty_query(pattern) do
      @store
      |> dirty_select(pattern)
      |> Enum.map(&to_que_job/1)
    end

    defp run_query(pattern) do
      run_dirty_query(pattern)
    end

    @result [:"$_"]
    def dirty_select(table, guards, opts \\ []) do
      attr_map   = table.__info__.query_map
      match_head = table.__info__.query_base
      guards     = Memento.Query.Spec.build(guards, attr_map)
      dirty_select_raw(table, [{ match_head, guards, @result }], opts)
    end

    def dirty_select_raw(table, match_spec, opts \\ []) do
      # Default options
      #lock   = Keyword.get(opts, :lock, :read)
      #limit  = Keyword.get(opts, :limit, nil)
      coerce = Keyword.get(opts, :coerce, true)

      # Use select/4 if there is limit, otherwise use select/3
      # Execute select method with the no. of args
      result = :mnesia.dirty_select(table, match_spec)

      # Coerce result conversion if `coerce: true`
      case coerce do
        true  -> coerce_records(result)
        false -> result
      end
    end

    defp coerce_records(records) when is_list(records) do
      Enum.map(records, &Memento.Query.Data.load/1)
    end

    defp coerce_records({records, _term}) when is_list(records) do
      coerce_records(records)
    end

    # Returns Job ID
    defp normalize_id(job) do
      cond do
        is_map(job) -> job.id
        true        -> job
      end
    end

    # Convert Que.Job to Mnesia Job
    defp to_db_job(%Que.Job{} = job) do
      struct(@store, Map.from_struct(job))
    end

    # Convert Mnesia DB Job to Que.Job
    defp to_que_job(nil), do: nil
    defp to_que_job(%@store{} = job) do
      struct(Que.Job, Map.from_struct(job))
    end

    # Read/Write/Delete to Table
    defp dirty_read(store, id) do
      case :mnesia.dirty_read(store, id) do
        []           -> nil
        [record | _] -> Memento.Query.Data.load(record)
      end
    end

    defp dirty_delete(store, id) do
      :mnesia.dirty_delete(store, id)
    end

    defp dirty_write(store, record) do
      struct = prepare_record_for_write!(store, record)
      tuple  = Memento.Query.Data.dump(struct)
      case :mnesia.dirty_write(store, tuple) do
        :ok  -> struct
        term -> term
      end
    end

    defp prepare_record_for_write!(table, record) do
      info     = table.__info__()
      autoinc? = Memento.Table.Definition.has_autoincrement?(table)
      primary  = Map.get(record, info.primary_key)

      cond do
        # If primary key is specified, don't do anything to the record
        not is_nil(primary) ->
          record

        # If primary key is not specified but autoincrement is enabled,
        # get the last numeric key and increment its value

        is_nil(primary) && autoinc? ->
          next_key = autoincrement_key_for(table)
          Map.put(record, info.primary_key, next_key)

        # If primary key is not specified and there is no autoincrement
        # enabled either, raise an error
        is_nil(primary) ->
          #IO.puts "ERROR| Memento records cannot have a nil primary key unless autoincrement is enabled"
          Memento.Error.raise(
            "Memento records cannot have a nil primary key unless autoincrement is enabled"
          )
      end
    end


    #---------------------
    # @TODO - I have a much more efficient mechanisms for a sequence generator need a way to drop in.
    #---------------------
    def autoincrement_key_for(table) do
      {:atomic, n} = :mnesia.transaction(fn ->
        n = case :mnesia.read(@auto_inc, table, :write) do
          [{@auto_inc, table, c}| _] -> c + 1
          o -> 0
        end
        :mnesia.write(@auto_inc, {@auto_inc, table, n}, :write)
        n
      end)
      n
    end

    defp read(id),      do: dirty_read(@store, id) #Memento.Query.read(@store, id)
    defp delete(id),    do: dirty_delete(@store, id) #Memento.Query.delete(@store, id)
    defp write(record), do: dirty_write(@store, record) #Memento.Query.write(record)
  end
end
