module Plumbing
  module Valve
    Message = Struct.new :message, :args, :params, :block, :result, :status
  end
end
