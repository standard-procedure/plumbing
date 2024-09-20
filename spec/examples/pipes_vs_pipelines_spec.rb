require "spec_helper"
require "plumbing/actor/async"
require "plumbing/actor/threaded"

RSpec.describe "Pipes vs Pipelines examples" do
  # standard:disable Lint/ConstantDefinitionInBlock
  class DogCounter < Plumbing::Pipeline
    perform :read_file
    perform :filter_dogs
    perform :count_lines

    pre_condition :must_be_a_file do |filename|
      File.exist? filename
    end

    post_condition :must_be_a_number do |output|
      output.is_a? Numeric
    end

    private

    def read_file filename
      File.read(filename).to_s.split("\n")
    end

    def filter_dogs lines
      lines.select { |line| line.downcase.include? "dog" }
    end

    def count_lines lines
      lines.count
    end
  end
  # standard:enable Lint/ConstantDefinitionInBlock

  Plumbing::Spec.modes do
    context "In #{Plumbing.config.mode} mode" do
      context "using a Pipeline" do
        it "counts the lines containing the word 'dog'" do
          filename = __dir__ + "/animals.txt"
          expect(DogCounter.new.call(filename)).to eq 2
        end
      end

      context "using a Pipe" do
        it "counts the lines containing the word 'dog'" do
          @count = 0

          @file_reader = Plumbing::Pipe.start
          @dog_filter = Plumbing::Pipe::Filter.start source: @file_reader do |event_name, data|
            data[:line].downcase.include? "dog"
          end
          @dog_filter.add_observer do |event_name, data|
            @count += 1
          end

          filename = __dir__ + "/animals.txt"
          File.read(filename).to_s.split("\n").each { |line| @file_reader.notify "line_read_from_file", line: line }

          expect { @count }.to become 2
        end
      end
    end
  end
end
