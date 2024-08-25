module Plumbing
  # A pipe that filters events from a source pipe
  class Junction < Pipe
    # Chain multiple sources to this pipe
    # @param [Array<Plumbing::Pipe>]
    def initialize *sources, dispatcher: nil
      super(dispatcher: dispatcher)
      @sources = sources.collect { |source| add(source) }
    end

    private

    def add source
      source.as(Observable).add_observer do |event|
        dispatch event
      end
      source
    end
  end
end
