# Pipes and Pipelines

[Pipes](/docs/pipes.md) and [Pipelines](/docs/pipelines.md) have very similar names and can be used to do the same things.

However, there are significant reasons why you may choose one over the other.

The classic "unix pipe" example is getting a word count from a text file.  For example, to count the number of lines containing the word "dog" in "animals.txt":
```sh
cat animals.txt | grep "dog" | wc -l
```

This could be implemented as a Pipeline like so:
```ruby
require "plumbing"
class DogCounter
  include Plumbing::Pipeline
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
    File.read(input[:filename]).to_s.split("\n")
  end

  def filter_dogs lines
    lines.select { |line| line.downcase.include? "dog" }
  end

  def count_lines lines
    lines.count
  end
end

DogCounter.new.call("animals.txt")
# => 2
```

Or you could implement it using Pipes:

```ruby
@count = 0

@file_reader = Plumbing::Pipe.start
@dog_filter = Plumbing::Pipe::Filter.start(source: @file_reader) { |event_name, data| data[:line].downcase.include? "dog" }
@dog_filter.add_observer { |event_name, data| @count += 1 }

File.read("animals.txt").to_s.split("\n").each { |line| @file_reader.notify "line_read_from_file", line: line }

puts @count
# => 2
```

The Pipe version looks much more complex and harder to follow.  That's because, although both take some input data and pass it along multiple stages, the Pipeline version is self-contained, whereas the Pipe version involves plugging two different pipes together and customising their behaviour.

However, note that the Pipe version is more flexible, even without writing a custom class.  We could easily add extra stages by hanging more filters or observers on the end of the pipeline, or we could reorder the steps by attaching the observers in different orders.  And, if we decide we are done with a particular stream of data, we could just remove the observer at run-time.  None of which is possible with a static Pipeline class.





