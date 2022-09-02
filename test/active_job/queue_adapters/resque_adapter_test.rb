require "test_helper"

class ActiveJob::QueueAdapters::ResqueAdapterTest < ActiveSupport::TestCase
  setup do
    @old_data_store = Resque.redis
  end

  teardown do
    Resque.redis = @old_data_store
  end

  test "create a new adapter with the default resque redis instance" do
    assert_no_changes -> { Resque.redis } do
      ActiveJob::QueueAdapters::ResqueAdapter.new
    end
  end

  test "activate configured redis instance on creation" do
    current_redis = current_resque_redis
    new_redis = create_redis "new_redis"

    assert_changes -> { current_resque_redis }, from: current_redis, to: new_redis do
      ActiveJob::QueueAdapters::ResqueAdapter.new(new_redis)
    end
  end

  test "activate a different redis instance" do
    old_redis = create_redis "old_redis"
    new_redis = create_redis "new_redis"
    adapter = ActiveJob::QueueAdapters::ResqueAdapter.new(new_redis)
    Resque.redis = old_redis

    assert_changes -> { current_resque_redis }, from: old_redis, to: new_redis do
      adapter.activate
    end
  end

  test "activating different redis connections is thread-safe" do
    redis_1 = create_redis("redis_1")
    adapter_1 = ActiveJob::QueueAdapters::ResqueAdapter.new(redis_1)
    redis_2 = create_redis("redis_2")
    adapter_2 = ActiveJob::QueueAdapters::ResqueAdapter.new(redis_2)

    { redis_1 => adapter_1, redis_2 => adapter_2 }.collect do |redis, adapter|
      50.times.collect do
        Thread.new do
          adapter.activate
          sleep rand / 10.0 # 0.0Xs delays to minimize active delays while ensuring race conditions
          assert_equal redis, current_resque_redis
        end
      end
    end.flatten.each(&:join)
  end

  test "use different queue adapters via active job" do
    redis_1 = create_redis("redis_1")
    adapter_1 = ActiveJob::QueueAdapters::ResqueAdapter.new(redis_1)
    redis_2 = create_redis("redis_2")
    adapter_2 = ActiveJob::QueueAdapters::ResqueAdapter.new(redis_2)

    adapter_1.activate

    5.times { DummyJob.perform_later }

    adapter_2.activate
    10.times { DummyJob.perform_later }

    adapter_1.activate
    assert_equal 5, ApplicationJob.jobs.pending.count

    adapter_2.activate
    assert_equal 10, ApplicationJob.jobs.pending.count
  end

  private
    def current_resque_redis
      Resque.redis.instance_variable_get("@redis")
    end

    def create_redis(name)
      Redis::Namespace.new "resque:#{name}", redis: @old_data_store
    end
end
