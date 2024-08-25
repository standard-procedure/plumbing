module Plumbing
  # A pipe that filters events from a source pipe
  class Junction < Pipe
    # Chain multiple sources to this pipe
    # @param [Array<Plumbing::Pipe>]
    def initialize *sources
      super()
      @sources = sources.collect { |source| add(source) }
    end

    private

    def add source
      raise InvalidSource.new "#{source} must be a Plumbing::Pipe descendant" unless source.is_a? Plumbing::Pipe
      source.add_observer do |event|
        dispatch event
      end
      source
    end
  end
end
