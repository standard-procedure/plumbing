# Configuration

## Mode

The most important configuration setting is the `mode`, which governs how background tasks are handled.

By default it is `:inline`, so every command or query is handled synchronously.  This is the ruby behaviour you know and love (although see the section on `await` below).

`:async` mode handles tasks using fibers (via the [Async gem](https://socketry.github.io/async/index.html)).  Your code should include the "async" gem in its bundle, as Plumbing does not load it by default.

`:threaded` mode handles tasks using a thread pool via [Concurrent Ruby](https://ruby-concurrency.github.io/concurrent-ruby/master/Concurrent/Promises.html)).  Your code should include the "concurrent-ruby" gem in its bundle, as Plumbing does not load it by default.

However, `:threaded` mode is not safe for Ruby on Rails applications.  In this case, use `:threaded_rails` mode, which is identical to `:threaded`, except it wraps the tasks in the Rails executor.  This ensures your actors do not interfere with the Rails framework.  Note that the Concurrent Ruby's default `:io` scheduler will create extra threads at times of high demand, which may put pressure on the ActiveRecord database connection pool.  A future version of plumbing will allow the thread pool to be adjusted with a maximum number of threads, preventing contention with the connection pool.

The `timeout` setting is used when performing queries - it defaults to 30s.

```ruby
  require "plumbing"
  require "async"
  puts Plumbing.config.mode
  # => :inline

  Plumbing.configure mode: :async, timeout: 10

  puts Plumbing.config.mode
  # => :async
```

If you are running a test suite, you can temporarily update the configuration by passing a block.

```ruby
  require "plumbing"
  require "async"
  puts Plumbing.config.mode
  # => :inline

  Plumbing.configure mode: :async do
    puts Plumbing.config.mode
    # => :async
    first_test
    second_test
  end

  puts Plumbing.config.mode
  # => :inline
```

## Logger

The configuration includes a default logger that is set to write to `stdout`.  The log level is set to `info`.

To understand what Plumbing is doing, under the hood, you can set the log level to `debug`:

```ruby
Plumbing.config.logger.level = :debug
```
This is especially useful if using actors (or pipes) and you are getting odd asynchronous behaviour.

Or you can replace the logger with your own:

```ruby
Plumbing.configure logger: MyFancyLogger.new
```