# frozen_string_literal: true

RSpec.describe "Plumbing::Actor sender stack" do
  before { Plumbing::Actor.uses :inline }

  let(:inner) do
    Class.new do
      include Plumbing::Actor
      async(:chain) { returns { current_senders } }
    end
  end

  let(:middle) do
    Class.new do
      include Plumbing::Actor
      async :go do
        param :inner, Object
        returns { |inner:| inner.chain(sender: self).await }
      end
    end
  end

  describe "current_senders" do
    it "exposes the full synchronous chain, outermost first" do
      i = inner.new
      m = middle.new
      top = inner.new

      chain = m.go(inner: i, sender: top).await

      expect(chain).to eq([top, m]) # outermost (top) -> immediate (m)
    end

    it "is empty at the top level before any message is in flight" do
      Fiber[Plumbing::Actor::FIBER_KEY] = nil
      expect(inner.new.current_senders).to eq([])
    end

    it "agrees with current_sender on the immediate caller" do
      probe = Class.new do
        include Plumbing::Actor
        async(:both) { returns { [current_sender, current_senders.last] } }
      end.new
      sender = inner.new

      immediate, chain_top = probe.both(sender: sender).await

      expect(immediate).to be(sender)
      expect(chain_top).to be(sender)
    end
  end

  describe "implementation method naming" do
    it "defines name, _name and _name_implementation" do
      klass = Class.new do
        include Plumbing::Actor
        async(:say) { returns { "hi" } }
      end

      methods = klass.instance_methods(false)
      expect(methods).to include(:say, :_say, :_say_implementation)
      expect(methods).not_to include(:_validated_say_implementation)
    end
  end
end
