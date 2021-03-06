[<img src='https://i.imgur.com/Eec71eh.png' alt='Que' width='200px' />][docs] 

The Noizu Labs, Inc. Fork
=============================================================================

[![Build Status][shield-travis]][travis-ci]
[![Coverage Status][shield-inch]][docs]
[![Version][shield-version]][hexpm]
[![License][shield-license]][hexpm]

> Simple Background Job Processing in Elixir :zap:

Que is a job processing library backed by [`Mnesia`][mnesia], a distributed
real-time database that comes with Erlang / Elixir. That means it doesn't
depend on any external services like `Redis` for persisting job state. This
makes it really easy to use since you don't need to install anything other
than Que itself.

See the [Documentation][docs].

<br>



# This @noizu fork adds some experimental features. 

## Priority may now be specified when queues jobs. 
  Only the values :pri0, :pri1, :pri2, :pri3 are currently available. 
  Jobs with :pri0 will execute before jobs with :pri1. 
  Jobs with :pri1 will execute before jobs with :pri2, etc.

  ```elixir
    # Create with default priority :pri1
    Que.add(App.Workers.ImageConverter, some_image)
     
    # Specify Priority 
    Que.add(:pri0, App.Workers.ImageConverter, some_image)
    
    # Convienence methods. 
    Que.pri0(App.Workers.ImageConverter, some_image)
    Que.pri1(App.Workers.ImageConverter, some_image)
    Que.pri2(App.Workers.ImageConverter, some_image)
    Que.pri3(App.Workers.ImageConverter, some_image)        
  ```

## ShardWorkers
  Available for situations where the GenServer call and queue update tasks themselves  become a bottle neck. 
  In shard workers the provided concurrency values controls the number of servers created with server processing one job
  at a time. Jobs are queued in the same was as to regular workers but the actual job is pushed randomly to one
  of the available shards. E.g. `Que.add(ShardWorker, :test)` pushes to `ShardWorker.Shard16`
      
  ShardWorkers are configured like standard workers.     
```elixir
    defmodule App.Workers.ImageConverter do
      use Que.ShardWorker
    
      def perform(image) do
        ImageTool.save_resized_copy!(image, :thumbnail)
        ImageTool.save_resized_copy!(image, :medium)
      end
    end
    
    Que.add(App.Workers.ImageConverter)
```    

## Dirty Operations & Throughput Optimization, Pluggable DB Adapters
  These changes all favor throughput over data correctness and, in the case of the ShardWorker change, order of execution.
  
  ### Plugable Database Adapters 
  
  A user may switch to dirty mnesia operations to avoid mnesia transaction bottle necks under high load.
  Additionally a more efficient auto increment implement has been provided to avoid table scans against very large data sets.    
  
  Add to your Config File to use: 
  `config :que, persistence_strategy: Que.Persistence.DirtyMnesia`
  
  ### Async Job Creation
  
  Replaced GenServer.Call for add worker with GenServer.cast to allow workers to pool up with out waiting on 
  confirmation. Note this breaks new functionality for returning job details on create. 
  
  Add to your Config File to use: 
  `config :que, async_add: true`
  
  ### Error Handler for very rapid process responses,
  Modified Process Monitor handler to treat :noproc responses (usually due to process completing 
  before the Monitor has been bound) as success. 
    

## Distributed System Tweaks
  Schema and queries have been modified to include the host node 
  this allows you to host persistent queues on multiple servers with
  out the tasks being duplicated on across nodes after restart. 
  Calls have been added to specify host queue.  
  
  In the future this may additionally be used in conjuction with a coordinater mechanism to  
  load balance tasks across servers.

  Add to your Config File to use: 
  `config :que, multi_tenant: true`
  
  ```elixir
    # remote_add uses :rpc.call
    Que.remote_add(:"node_in_cluster@domain.com", DistributedWorker, arguments) 
    Que.remote_add(:"node_in_cluster@domain.com", :pri3, DistributedWorker, arguments)
    
    # remote_async_add uses :rpc.cast
    Que.remote_async_add(:"node_in_cluster@domain.com", DistributedWorker, arguments) 
    Que.remote_async_add(:"node_in_cluster@domain.com", :pri3, DistributedWorker, arguments)
  ```
  
  Although in the future I may will add load balancing support and availabilty checks you may implement crude balancing
  on your own using a randomized or round robing approach. 
  
  ### Example Randomized Load Balancer
  ```elixir
    # You may implement a very simple randomized load balancer such as
    cluser = [:"node1@domain.com", :"node2@domaint.com"] 
    Que.remote_async_add(Enum.random(cluster), DistributedWorker, arguments) 
  ```
    
  ### Example Round Robin Load Balancer 
  ```elixir
    @table :round_robin_cluster
    :ets.new(@table, [:set, :public, :named_table, {:write_concurrency, true}])
    
    cluster = [:"node1@domain.com", :"node2@domaint.com"]
    cluster_size = length(cluster)         

    index = :ets.update_counter(@table, DistributedWorker, {2, 1, cluster_size - 1, 0}, {DistributedWorker, 0})     
    Que.remote_async_add(Enum.at(cluster, index), DistributedWorker, [argument: :list])
  ```

## Breaking Changes 
  Functionality will be very similar to stock QUE behavior if not configuration options are selected,
  however the Jobs table has been updated to include a node and priority filed and will need to be regenerated if migrating to this fork.

## Running Tests 
  To run tests with the experimental features enabled simply run
  `MIX_ENV=noizu_test mix test`
    
# Installation

Add `que` to your project dependencies in `mix.exs`:

```elixir
def deps do
  [{:que, github: "noizu/que", tag: "0.10.1"}]  
end
```

and then add it to your list of `applications`: (not required on newer version of elixir)
```elixir
def application do
  [applications: [:que]]
end
```


## Mnesia Setup

Que runs out of the box, but by default all jobs are stored in-memory.
To persist jobs across application restarts, specify the DB path in
your `config.exs`:

```elixir
config :mnesia, dir: 'mnesia/#{Mix.env}/#{node()}'        # Notice the single quotes
```

And run the following mix task:

```bash
$ mix que.setup
```

This will create the Mnesia schema and job database for you. For a
detailed guide, see the [Mix Task Documentation][docs-mix]. For
compiled releases where `Mix` is not available
[see this][docs-setup-prod].

<br>




# Usage

Que is very similar to other job processing libraries such as Ku and
Toniq. Start by defining a [`Worker`][docs-worker] with a `perform/1`
callback to process your jobs:

```elixir
defmodule App.Workers.ImageConverter do
  use Que.Worker

  def perform(image) do
    ImageTool.save_resized_copy!(image, :thumbnail)
    ImageTool.save_resized_copy!(image, :medium)
  end
end
```

You can now add jobs to be processed by the worker:

```elixir
Que.add(App.Workers.ImageConverter, some_image)
#=> {:ok, %Que.Job{...}}
```


## Pattern Matching

The argument here can be any term from a Tuple to a Keyword List
or a Struct. You can also pattern match and use guard clauses like
any other method:

```elixir
defmodule App.Workers.NotificationSender do
  use Que.Worker

  def perform(type: :like, to: user, count: count) do
    User.notify(user, "You have #{count} new likes on your posts")
  end

  def perform(type: :message, to: user, from: sender) do
    User.notify(user, "You received a new message from #{sender.name}")
  end

  def perform(to: user) do
    User.notify(user, "New activity on your profile")
  end
end

# Allowing for syntaxically pretty api calls such as 
Que.add(App.Workers.NotificationSender, type: :message, to: "keith", from: "admin")
# Or less ambigiously
Que.add(App.Workers.NotificationSender, [type: :message, to: "keith", from: "admin"])

```


## Concurrency

By default, all workers process one Job at a time, but you can
customize that by passing the `concurrency` option:

```elixir
defmodule App.Workers.SignupMailer do
  use Que.Worker, concurrency: 4

  def perform(email) do
    Mailer.send_email(to: email, message: "Thank you for signing up!")
  end
end
```


## Job Success / Failure Callbacks

The worker can also export optional `on_success/1` and `on_failure/2`
callbacks that handle appropriate cases.

```elixir
defmodule App.Workers.ReportBuilder do
  use Que.Worker

  def perform({user, report}) do
    report.data
    |> PDFGenerator.generate!
    |> File.write!("reports/#{user.id}/report-#{report.id}.pdf")
  end

  def on_success({user, _}) do
    Mailer.send_email(to: user.email, subject: "Your Report is ready!")
  end

  def on_failure({user, report}, error) do
    Mailer.send_email(to: user.email, subject: "There was a problem generating your report")
    Logger.error("Could not generate report #{report.id}. Reason: #{inspect(error)}")
  end
end

# Allowing for syntactically pretty api calls such as 
Que.add(App.Workers.NotificationSender, type: :message, to: "keith", from: "admin")
# Or less ambigiously
Que.add(App.Workers.NotificationSender, [type: :message, to: "keith", from: "admin"])


```


## Setup and Teardown

You can similarly export optional `on_setup/1` and `on_teardown/1` callbacks
that are respectively run before and after the job is performed (successfully
or not). But instead of the job arguments, they pass the job struct as an
argument which holds a lot more internal details that can be useful for custom
features such as logging, metrics, requeuing and more.

```elixir
defmodule MyApp.Workers.VideoProcessor do
  use Que.Worker

  def on_setup(%Que.Job{} = job) do
    VideoMetrics.record(job.id, :start, process: job.pid, status: :starting)
  end

  def perform({user, video, options}) do
    User.notify(user, "Your video is processing, check back later.")
    FFMPEG.process(video.path, options)
  end

  def on_teardown(%Que.Job{} = job) do
    {user, video, _options} = job.arguments
    link = MyApp.Router.video_path(user.id, video.id)

    VideoMetrics.record(job.id, :end, status: job.status)
    User.notify(user, "We've finished processing your video. See the results.", link)
  end
end

```


Head over to Hexdocs for detailed [`Worker` documentation][docs-worker].

<br>




# Roadmap

 - [x] Write Documentation
 - [x] Write Tests
 - [x] Persist Job State to Disk
    - [x] Provide an API to interact with Jobs
 - [x] Add Concurrency Support
    - [x] Make jobs work in Parallel
    - [x] Allow customizing the number of concurrent jobs
 - [x] Success/Failure Callbacks
 - [x] Find a more reliable replacement for Amnesia
 - [ ] Delayed Jobs
 - [ ] Allow job cancellation
 - [ ] Job Priority
 - [ ] Support running in a multi-node enviroment
    - [ ] Recover from node failures
 - [ ] Support for more Persistence Adapters
    - [ ] Redis
    - [ ] Postgres
 - [x] Mix Task for creating Mnesia Database
 - [ ] Better Job Failures
    - [ ] Option to set timeout on workers
    - [ ] Add strategies to automatically retry failed jobs
 - [ ] Web UI

<br>




# Contributing

 - [Fork][github-fork], Enhance, Send PR
 - Lock issues with any bugs or feature requests
 - Implement something from Roadmap
 - Spread the word :heart:

<br>




# License

This package is available as open source under the terms of the [MIT License][license].

<br>

  [logo]:             https://i.imgur.com/Eec71eh.png
  [shield-version]:   https://img.shields.io/hexpm/v/que.svg
  [shield-license]:   https://img.shields.io/hexpm/l/que.svg
  [shield-downloads]: https://img.shields.io/hexpm/dt/que.svg
  [shield-travis]:    https://img.shields.io/travis/sheharyarn/que/master.svg
  [shield-inch]:      https://inch-ci.org/github/sheharyarn/que.svg?branch=master

  [travis-ci]:        https://travis-ci.org/sheharyarn/que
  [inch-ci]:          https://inch-ci.org/github/sheharyarn/que

  [license]:          https://opensource.org/licenses/MIT
  [mnesia]:           http://erlang.org/doc/man/mnesia.html
  [hexpm]:            https://hex.pm/packages/que

  [docs]:             https://hexdocs.pm/que
  [docs-worker]:      https://hexdocs.pm/que/Que.Worker.html
  [docs-mix]:         https://hexdocs.pm/que/Mix.Tasks.Que.Setup.html
  [docs-setup-prod]:  https://hexdocs.pm/que/Que.Persistence.Mnesia.html#setup!/0

  [github-fork]:      https://github.com/sheharyarn/que/fork
  

