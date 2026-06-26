# frozen_string_literal: true

RSpec.describe Plumbing do
  describe ".OneOf" do
    it "returns a proc that matches values within the set" do
      predicate = Plumbing.OneOf(:waiting, :done, :error)
      expect(predicate.call(:waiting)).to be true
      expect(predicate.call(:done)).to be true
      expect(predicate.call(:error)).to be true
    end

    it "returns false for values outside the set" do
      predicate = Plumbing.OneOf(:a, :b)
      expect(predicate.call(:c)).to be false
    end

    it "matches strictly without coercion (Symbol vs String)" do
      predicate = Plumbing.OneOf(:waiting)
      expect(predicate.call("waiting")).to be false
      expect(predicate.call(:waiting)).to be true
    end

    it "supports nil as one of the permitted values" do
      expect(Plumbing.OneOf(nil, :a).call(nil)).to be true
      expect(Plumbing.OneOf(:a, :b).call(nil)).to be false
    end

    it "supports arbitrary value types" do
      expect(Plumbing.OneOf(1, 2, 3).call(2)).to be true
      expect(Plumbing.OneOf("yes", "no").call("yes")).to be true
      expect(Plumbing.OneOf(true, false).call(false)).to be true
    end

    it "can be used as a Literal type predicate" do
      klass = Class.new(Literal::Struct) do
        prop :status, Plumbing.OneOf(:waiting, :done, :error), default: :waiting
      end

      expect(klass.new.status).to eq :waiting
      expect(klass.new(status: :done).status).to eq :done
      expect { klass.new(status: :exploded) }.to raise_error(Literal::TypeError)
    end
  end
end
