# frozen_string_literal: true

RSpec.describe Plumbing::Operation do
  describe "events" do
    let(:doubler_class) do
      Class.new(Plumbing::Operation) do
        prop :n, Integer
        prop :result, _Nilable(Integer)

        action :double do
          @result = @n * 2
        end
        go_to :done

        result :done
      end
    end

    it "emits Started, Transitioned and Completed to the pipeline in order" do
      events = []

      doubler_class.new(n: 4).tap do |d|
        d.add_observer { |event| events << event }
        d.start
      end

      expect(events.map(&:class)).to eq [
        Plumbing::Operation::Started,
        Plumbing::Operation::Transitioned,
        Plumbing::Operation::Completed
      ]
    end
  end
end
