require "spec_helper"
require_relative "../../../lib/plumbing/actor/transporter"

RSpec.describe Plumbing::Actor::Transporter do
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

  before do
    GlobalID.app = "rspec"
    GlobalID::Locator.use :rspec do |gid, options|
      Record.new gid.model_id
    end
  end

  context "marshalling" do
    it "passes simple arguments" do
      @transporter = described_class.new

      @transport = @transporter.marshal "Hello"
      expect(@transport).to eq ["Hello"]

      @transport = @transporter.marshal 1, 2, 3
      expect(@transport).to eq [1, 2, 3]
    end

    it "copies arrays" do
      @transporter = described_class.new

      @source = [[1, 2, 3], [:this, :that]]

      @transport = @transporter.marshal(*@source)
      expect(@transport).to eq @source
      expect(@transport.first.object_id).to_not eq @source.first.object_id
      expect(@transport.last.object_id).to_not eq @source.last.object_id
    end

    it "copies hashss" do
      @transporter = described_class.new

      @source = [{first: "1", second: 2}]

      @transport = @transporter.marshal(*@source)
      expect(@transport).to eq @source
      expect(@transport.first.object_id).to_not eq @source.first.object_id
    end

    it "converts objects to Global ID strings" do
      @transporter = described_class.new

      @record = Record.new 123
      @global_id = @record.to_global_id.to_s

      @transport = @transporter.marshal @record

      expect(@transport).to eq [@global_id]
    end

    it "converts objects within arrays to Global ID strings" do
      @transporter = described_class.new

      @record = Record.new 123
      @global_id = @record.to_global_id.to_s

      @transport = @transporter.marshal [:this, @record]

      expect(@transport).to eq [[:this, @global_id]]
    end

    it "converts objects within hashes to Global ID strings" do
      @transporter = described_class.new

      @record = Record.new 123
      @global_id = @record.to_global_id.to_s

      @transport = @transporter.marshal this: "that", the_other: {embedded: @record}

      expect(@transport).to eq [{this: "that", the_other: {embedded: @global_id}}]
    end
  end

  context "unmarshalling" do
    it "passes simple arguments" do
      @transporter = described_class.new

      @transport = @transporter.unmarshal "Hello"
      expect(@transport).to eq ["Hello"]

      @transport = @transporter.unmarshal 1, 2, 3
      expect(@transport).to eq [1, 2, 3]
    end

    it "passes arrays" do
      @transporter = described_class.new

      @transport = @transporter.unmarshal [1, 2, 3], [:this, :that]

      expect(@transport.first.object_id).to_not eq [1, 2, 3]
      expect(@transport.last.object_id).to_not eq [:this, :that]
    end

    it "passes hashss and keyword arguments" do
      @transporter = described_class.new

      @transport = @transporter.unmarshal first: "1", second: 2
      expect(@transport).to eq [{first: "1", second: 2}]
    end

    it "passes mixtures of arrays and hashes" do
      @transporter = described_class.new

      @transport = @transporter.unmarshal :this, :that, first: "1", second: 2
      expect(@transport).to eq [:this, :that, {first: "1", second: 2}]
    end

    it "converts Global ID strings to objects" do
      @transporter = described_class.new

      @record = Record.new "123"
      @global_id = @record.to_global_id.to_s

      @transport = @transporter.unmarshal @global_id

      expect(@transport).to eq [@record]
    end

    it "deals with errors when unpacking a Global ID" do
      @transporter = described_class.new

      @record = Record.new "123"
      @global_id = @record.to_global_id.to_s
      puts @global_id

      @transport = @transporter.unmarshal @global_id

      expect(@transport).to eq [@record]
    end

    it "converts Global ID strings within arrays to objects" do
      @transporter = described_class.new

      @record = Record.new "123"
      @global_id = @record.to_global_id.to_s

      @transport = @transporter.unmarshal :this, @global_id

      expect(@transport).to eq [:this, @record]
    end

    it "converts Global ID strings within hashes to objects" do
      @transporter = described_class.new

      @record = Record.new "123"
      @global_id = @record.to_global_id.to_s

      @transport = @transporter.unmarshal this: "that", the_other: {embedded: @global_id}

      expect(@transport).to eq [{this: "that", the_other: {embedded: @record}}]
    end
  end
end
