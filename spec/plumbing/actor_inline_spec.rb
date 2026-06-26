# frozen_string_literal: true

RSpec.describe Plumbing::Actor::Inline do
  # `:inline` is the default worker; reset explicitly in case a prior spec
  # has left the registry pointing somewhere else.
  before { Plumbing::Actor.uses :inline }

  describe "configuration" do
    it "produces actors backed by an Inline worker by default" do
      klass = Class.new do
        include Plumbing::Actor

        async(:noop) { returns { :ok } }
      end
      expect(klass.new.worker).to be_a(Plumbing::Actor::Inline)
    end
  end

  describe "dispatch" do
    let(:greeter) do
      Class.new do
        include Plumbing::Actor

        async :greet do
          param :name, String
          returns { |name:| "Hello #{name}" }
        end
      end
    end

    it "returns an Inline::Message" do
      expect(greeter.new.greet(name: "X")).to be_a(Plumbing::Actor::Inline::Message)
    end

    it "delivers synchronously so status is :done before the caller sees the message" do
      message = greeter.new.greet(name: "X")
      expect(message.status).to eq :done
    end

    it "exposes the result via .await" do
      expect(greeter.new.greet(name: "Cher").await).to eq "Hello Cher"
    end

    it "works with the Kernel#await block form" do
      actor = greeter.new
      expect(await { actor.greet(name: "World") }).to eq "Hello World"
    end
  end

  describe "type validation" do
    let(:typed) do
      Class.new do
        include Plumbing::Actor

        async :greet do
          param :name, String
          param :age, _Integer(0..120), default: 42
          returns { |name:, age:| "#{name} is #{age}" }
        end
      end
    end

    it "applies defaults when params are omitted" do
      expect(typed.new.greet(name: "Alice").await).to eq "Alice is 42"
    end

    it "raises Literal::TypeError on type mismatch" do
      expect { typed.new.greet(name: 123).await }.to raise_error(Literal::TypeError)
    end

    it "raises Literal::TypeError on range violation" do
      expect { typed.new.greet(name: "A", age: 200).await }.to raise_error(Literal::TypeError)
    end

    it "raises ArgumentError when a required param is missing" do
      expect { typed.new.greet.await }.to raise_error(ArgumentError, /missing keyword/)
    end
  end

  describe "exception propagation" do
    let(:exploding) do
      Class.new do
        include Plumbing::Actor

        async(:boom) { returns { raise "Kaboom!" } }
      end
    end

    it "re-raises the implementation exception when awaited" do
      message = exploding.new.boom
      expect { message.await }.to raise_error(RuntimeError, "Kaboom!")
    end

    it "captures the exception and status without raising on dispatch" do
      message = exploding.new.boom
      expect(message.status).to eq :error
      expect(message.exception).to be_a(RuntimeError)
    end

    it "clears the fiber-local current_sender even when the implementation raises" do
      Fiber[Plumbing::Actor::FIBER_KEY] = nil
      actor = exploding.new
      sender = exploding.new
      begin
        actor.boom(sender: sender).await
      rescue RuntimeError
        # expected
      end
      expect(Fiber[Plumbing::Actor::FIBER_KEY]).to be_nil
    end
  end

  describe "definition errors" do
    it "raises ArgumentError at class-load time when `returns` is omitted" do
      expect {
        Class.new do
          include Plumbing::Actor

          async :forgotten do
            param :name, String
          end
        end
      }.to raise_error(ArgumentError, /requires a `returns \{ \.\.\. \}` block/)
    end
  end

  describe "current_sender" do
    let(:probe) do
      Class.new do
        include Plumbing::Actor

        async(:who_sent) { returns { current_sender } }
      end
    end

    let(:other) do
      Class.new do
        include Plumbing::Actor

        async(:noop) { returns { :ok } }
      end
    end

    it "is nil when no sender is given" do
      expect(probe.new.who_sent.await).to be_nil
    end

    it "is the actor that sent the message" do
      actor = probe.new
      sender = other.new
      expect(actor.who_sent(sender: sender).await).to be(sender)
    end

    it "is nil at the top level before any message is in flight" do
      Fiber[Plumbing::Actor::FIBER_KEY] = nil
      expect(probe.new.current_sender).to be_nil
    end

    describe "save/restore across nested inline calls" do
      let(:inspector) do
        Class.new do
          include Plumbing::Actor

          async(:who_sent) { returns { current_sender } }
        end
      end

      let(:wrapper) do
        Class.new do
          include Plumbing::Actor

          async :wrap do
            param :inner, Object
            returns do |inner:|
              # Capture sender state at three points: before the nested call,
              # what the nested call sees, and after the nested call returns.
              before_nested = current_sender
              inner_sees = inner.who_sent(sender: self).await
              after_nested = current_sender
              [before_nested, inner_sees, after_nested]
            end
          end
        end
      end

      it "preserves the outer sender across a nested call" do
        outer = wrapper.new
        inner = inspector.new
        caller = inspector.new

        before, inner_saw_outer, after = outer.wrap(inner: inner, sender: caller).await

        expect(before).to be(caller)         # outer sees its own caller
        expect(inner_saw_outer).to be(outer) # inner sees outer (its caller)
        expect(after).to be(caller)          # outer's view restored after inner returns
      end
    end
  end

  describe "user-supplied block" do
    # The implementation is defined as a real method on the host class
    # (`_<name>_implementation`) so the call-site block flows
    # through to it as `&block`. `yield` is unreachable because the parser
    # rejects it inside a proc literal — use `&block` instead.
    it "is accessible inside the implementation via &block" do
      klass = Class.new do
        include Plumbing::Actor

        async :greet do
          param :name, String
          returns { |name:, &block| block&.call("Hello #{name}") }
        end
      end

      captured = nil
      klass.new.greet(name: "X") { |result| captured = result }.await
      expect(captured).to eq "Hello X"
    end

    it "is nil when no block is supplied at the call site" do
      klass = Class.new do
        include Plumbing::Actor

        async :probe do
          returns { |&block| block }
        end
      end

      expect(klass.new.probe.await).to be_nil
    end

    it "leaves the implementation result unchanged regardless of the block" do
      klass = Class.new do
        include Plumbing::Actor

        async :greet do
          param :name, String
          returns do |name:, &block|
            block&.call(name)
            "result:#{name}"
          end
        end
      end

      message = klass.new.greet(name: "X") { :ignored_side_effect }
      expect(message.await).to eq "result:X"
    end
  end

  describe "reply pattern" do
    # The non-blocking reply pattern: a Caller fires a fire-and-forget message
    # at a Worker, passing `sender: self`. The Worker, after doing its work,
    # calls `current_sender.something(...)` to reply — itself a fire-and-forget
    # message back to the caller. No `.await` from inside either implementation,
    # so neither side can deadlock the other.
    let(:worker_class) do
      Class.new do
        include Plumbing::Actor

        async :perform do
          param :payload, String
          returns do |payload:|
            current_sender&.receive_reply(text: "echo: #{payload}")
            :acked
          end
        end
      end
    end

    let(:caller_class) do
      Class.new do
        include Plumbing::Actor

        attr_reader :replies

        def initialize
          super
          @replies = []
        end

        async :start do
          param :worker, Object
          returns do |worker:|
            worker.perform(payload: "ping-1", sender: self)
            worker.perform(payload: "ping-2", sender: self)
            :dispatched
          end
        end

        async :receive_reply do
          param :text, String
          returns { |text:| @replies << text }
        end
      end
    end

    it "lets a worker reply to its sender without anyone blocking on await" do
      worker = worker_class.new
      caller = caller_class.new

      # Inline dispatch is synchronous, so by the time start returns, both
      # `perform` calls have run to completion (each one synchronously
      # firing `receive_reply` on the caller before returning).
      caller.start(worker: worker).await

      expect(caller.replies).to eq ["echo: ping-1", "echo: ping-2"]
    end

    it "leaves current_sender nil at the outermost level after the chain unwinds" do
      worker = worker_class.new
      caller = caller_class.new

      caller.start(worker: worker).await

      expect(Fiber[Plumbing::Actor::FIBER_KEY]).to be_nil
    end
  end
end
