# frozen_string_literal: true

RSpec.shared_examples "a deferred worker" do
  describe "delays dispatch of a message" do
    let(:counter_class) do
      Class.new do
        include Plumbing::Actor

        prop :count, _Integer, default: 0, reader: true

        async :tick do
          calls { @count += 1 }
        end
      end
    end

    it "is called after waiting for a period of time" do
      counter = counter_class.start

      counter.after(0.05, call: :tick)
      expect(counter.count.await).to eq 0
      sleep 0.1
      expect(counter.count.await).to eq 1
    end

    it "is not called if cancelled" do
      counter = counter_class.start

      message = counter.after(0.05, call: :tick)
      counter.cancel_deferred message
      sleep 0.1
      expect(counter.count.await).to eq 0
    end
  end
end
