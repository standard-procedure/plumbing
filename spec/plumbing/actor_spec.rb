require "spec_helper"

require_relative "../../lib/plumbing/actor/async"
require_relative "../../lib/plumbing/actor/threaded"
require_relative "../../lib/plumbing/actor/rails"

RSpec.describe Plumbing::Actor do
  # standard:disable Lint/ConstantDefinitionInBlock
  class Counter
    include Plumbing::Actor
    async :name, :count, :slow_query, "slowly_increment", "raises_error"
    attr_reader :name, :count

    def initialize name, initial_value: 0
      @name = name
      @count = initial_value
    end

    protected

    def slowly_increment
      sleep 0.2
      @count += 1
    end

    def slow_query
      sleep 0.2
      @count
    end

    def raises_error = raise "I'm an error"
  end

  class StepCounter < Counter
    async :step_value
    attr_reader :step_value

    def initialize name, initial_value: 0, step_value: 5
      super(name, initial_value: initial_value)
      @step_value = step_value
    end

    protected

    def slowly_increment
      sleep 0.2
      @count += @step_value
    end

    def failing_query
      raise "I'm a failure"
    end
  end

  class WhoAmI
    include Plumbing::Actor
    async :me_as_actor, :me_as_self

    private

    def me_as_actor = as_actor

    def me_as_self = self

    def prepare = @calling_thread = Thread.current

    def check = @calling_thread == Thread.current
  end

  class Actor
    include Plumbing::Actor
    async :get_object_id, :get_object

    private def get_object_id(record) = record.object_id
    private def get_object(record) = record
  end

  class SafetyCheck
    include Plumbing::Actor
    async :called_from_actor_thread?

    def initialize tester
      @tester = tester
      @called_from_actor_thread = false
      configure_safety_check
    end

    private

    def called_from_actor_thread? = @called_from_actor_thread

    def configure_safety_check
      @tester.on_safety_check do
        safely do
          @called_from_actor_thread = proxy.in_context?
        end
      end
    end
  end

  class Tester
    include Plumbing::Actor
    async :on_safety_check, :do_safety_check

    def initialize
      @on_safety_check = nil
    end

    private

    def on_safety_check(&block) = @on_safety_check = block

    def do_safety_check = @on_safety_check&.call
  end

  class ParameterHandler
    include Plumbing::Actor
    async :set_values, :args, :params, :block
    attr_reader :args, :params, :block

    def initialize
      @args = nil
      @params = nil
      @block = nil
    end

    private

    def set_values *args, **params, &block
      @args = args
      @params = params
      @block = block
    end
  end
  # standard:enable Lint/ConstantDefinitionInBlock

  Plumbing::Spec.modes do
    context "In #{Plumbing.config.mode} mode" do
      it "knows which async messages are understood" do
        expect(Counter.async_messages).to eq [:name, :count, :slow_query, :slowly_increment, :raises_error]
      end

      it "reuses existing proxy classes" do
        @counter = Counter.start "inline counter", initial_value: 100
        @proxy_class = @counter.class

        @counter = Counter.start "another inline counter", initial_value: 200
        expect(@counter.class).to eq @proxy_class
      end

      it "includes async messages from the superclass" do
        expect(StepCounter.async_messages).to eq [:name, :count, :slow_query, :slowly_increment, :raises_error, :step_value]

        @step_counter = StepCounter.start "step counter", initial_value: 100, step_value: 10

        expect(@step_counter.count.value).to eq 100
        expect(@step_counter.step_value.value).to eq 10
        @step_counter.slowly_increment
        expect(@step_counter.count.value).to eq 110
      end

      it "can access its own proxy" do
        @actor = WhoAmI.start

        expect(await { @actor.me_as_self }).to_not eq @actor
        expect(await { @actor.me_as_actor }).to eq @actor
      end

      it "sends a single positional parameter" do
        @parameter_handler = ParameterHandler.start

        @parameter_handler.set_values "this"
        expect(await { @parameter_handler.args }).to eq ["this"]
      end

      it "sends multiple positional parameters" do
        @parameter_handler = ParameterHandler.start

        @parameter_handler.set_values "this", "that"
        expect(await { @parameter_handler.args }).to eq ["this", "that"]
      end

      it "sends keyword parameters" do
        @parameter_handler = ParameterHandler.start

        @parameter_handler.set_values something: "for nothing", cat: "dog", number: 123
        expect(await { @parameter_handler.params }).to eq({something: "for nothing", cat: "dog", number: 123})
      end

      it "sends a mix of positional and keyword parameters" do
        @parameter_handler = ParameterHandler.start

        @parameter_handler.set_values "what do you say", 123, something: "for nothing"
        expect(await { @parameter_handler.args }).to eq ["what do you say", 123]
        expect(await { @parameter_handler.params }).to eq({something: "for nothing"})
      end

      it "sends a block parameter" do
        @parameter_handler = ParameterHandler.start

        @parameter_handler.set_values do
          "HELLO"
        end

        @block = await { @parameter_handler.block }
        expect(@block.call).to eq "HELLO"
      end

      it "sends a mix of positional and keyword parameters with a block" do
        @parameter_handler = ParameterHandler.start

        @parameter_handler.set_values "what do you say", 123, something: "for nothing" do
          "BOOM"
        end

        expect(await { @parameter_handler.args }).to eq ["what do you say", 123]
        expect(await { @parameter_handler.params }).to eq({something: "for nothing"})
        @block = await { @parameter_handler.block }
        expect(@block.call).to eq "BOOM"
      end
    end
  end

  context "Inline mode only" do
    around :example do |example|
      Plumbing.configure mode: :inline, &example
    end

    it "returns the result from a message immediately" do
      @counter = Counter.start "inline counter", initial_value: 100
      @time = Time.now

      expect(@counter.name.value).to eq "inline counter"
      expect(@counter.count.value).to eq 100
      expect(Time.now - @time).to be < 0.1

      expect(@counter.slow_query.value).to eq 100
      expect(Time.now - @time).to be > 0.1
    end

    it "executes all messages immediately" do
      @counter = Counter.start "inline counter", initial_value: 100
      @time = Time.now

      @counter.slowly_increment

      expect(@counter.count.value).to eq 101
      expect(Time.now - @time).to be > 0.1
    end

    it "can safely access its own data" do
      @tester = Tester.start
      @safety_check = SafetyCheck.start @tester

      @tester.do_safety_check

      expect { @safety_check.called_from_actor_thread?.value }.to become_true
    end
  end

  [:threaded, :async].each do |mode|
    context "Asynchronously (#{mode})" do
      around :example do |example|
        Sync do
          Plumbing.configure mode: mode, &example
        end
      end

      it "sends messages to run in the background" do
        @counter = Counter.start "async counter", initial_value: 100

        @time = Time.now
        @name = @counter.name
        expect(Time.now - @time).to be < 0.2

        @time = Time.now
        @count = @counter.count
        expect(Time.now - @time).to be < 0.2

        @time = Time.now
        @counter.slow_query
        expect(Time.now - @time).to be < 0.2
      ensure
        @counter.stop
      end

      it "waits for the result of messages" do
        @counter = Counter.start "threaded counter", initial_value: 100
        @time = Time.now

        await { @counter.slowly_increment }

        expect { @counter.count.value }.to become 101
        expect(Time.now - @time).to be > 0.1
      ensure
        @counter.stop
      end

      it "re-raises exceptions when checking the result" do
        @counter = Counter.start "failure"

        expect { @counter.raises_error.value }.to raise_error "I'm an error"
      ensure
        @counter.stop
      end

      it "does not raise exceptions if ignoring the result" do
        @counter = Counter.start "failure"

        expect { @counter.raises_error }.not_to raise_error
      ensure
        @counter.stop
      end
    end
  end

  context "Threaded mode only" do
    around :example do |example|
      Plumbing.configure mode: :threaded, &example
    end

    before do
      GlobalID.app = "rspec"
      GlobalID::Locator.use :rspec do |gid, options|
        Record.new gid.model_id
      end
    end

    # standard:disable Lint/ConstantDefinitionInBlock
    class Record
      include GlobalID::Identification
      attr_reader :id
      def initialize id
        @id = id
      end

      def == other
        other.id == @id
      end
    end
    # standard:enable Lint/ConstantDefinitionInBlock

    it "packs and unpacks arguments when sending them across threads" do
      @actor = Actor.start
      @record = Record.new "999"

      @object_id = @actor.get_object_id(@record).value

      expect(@object_id).to_not eq @record.object_id
    ensure
      @actor.stop
    end

    it "packs and unpacks results when sending them across threads" do
      @actor = Actor.start
      @record = Record.new "999"

      @object = @actor.get_object(@record).value

      expect(@object.id).to eq @record.id
      expect(@object.object_id).to_not eq @record.object_id
    ensure
      @actor.stop
    end

    it "can safely access its own data" do
      @tester = Tester.start
      @safety_check = SafetyCheck.start @tester

      @tester.do_safety_check

      expect { @safety_check.called_from_actor_thread?.value }.to become_true
    ensure
      @tester.stop
      @safety_check.stop
    end
  end
end
