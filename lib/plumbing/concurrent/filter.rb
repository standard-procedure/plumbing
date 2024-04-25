# if RUBY_ENGINE != "opal"
#   require_relative "../filter"
#   require_relative "pipe"
#
#   module Plumbing
#     module Concurrent
#       # A pipe that filters events from a source pipe
#       class Filter < Pipe
#         # Chain this pipe to the source pipe
#         # @param source [Plumbing::BlockedPipe]
#         # @param accepts [Array[String]] event types that this filter will allow through (or pass [] to allow all)
#         # @param rejects [Array[String]] event types that this filter will not allow through
#         def initialize source:, accepts: [], rejects: []
#           super()
#           @observer = Ractor.new(accepts.freeze, rejects.freeze) do |accepted_types, rejected_types|
#             while (event = Ractor.receive) != :shutdown
#               Ractor.yield event if !(accepted_types.any? && !accepted_types.include?(event.type)) && !rejected_types.include?(event.type)
#             end
#           end
#           Types::Source[source].add_observer @observer
#         end
#
#         attr_reader :accepted_event_types
#         attr_reader :rejected_event_types
#
#         def shutdown
#           @observer << :shutdown
#           super()
#         end
#       end
#     end
#   end
# end
