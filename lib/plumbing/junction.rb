module Plumbing
  # A pipe that filters events from a source pipe
  class Junction < Pipe
    # Chain multiple sources to this pipe
    # @param sources [Array<Plumbing::Observable>] the sources which will be joined and relayed
    def initialize *sources
      super()
      sources.each { |source| add(source) }
    end

    private

    def add source
      source.as(Observable).add_observer do |event|
        safely do
          dispatch event
        end
      end
    end
  end
end
