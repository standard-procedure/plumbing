require "global_id"

module Plumbing
  module Actor
    class Transporter
      def marshal *arguments
        pack_array arguments
      end

      def unmarshal *arguments
        unpack_array arguments
      end

      private

      def pack argument
        case argument
        when GlobalID::Identification then pack_global_id argument
        when Array then pack_array argument
        when Hash then pack_hash argument
        else argument.clone
        end
      end

      def pack_array arguments
        arguments.map { |a| pack a }
      end

      def pack_hash arguments
        arguments.transform_values { |v| pack v }
      end

      def pack_global_id argument
        argument.to_global_id.to_s
      end

      def unpack argument
        case argument
        when String then unpack_string argument
        when Array then unpack_array argument
        when Hash then unpack_hash argument
        else argument
        end
      end

      def unpack_array arguments
        arguments.map { |a| unpack a }
      end

      def unpack_hash arguments
        arguments.to_h do |key, value|
          [key, unpack(value)]
        end
      end

      def unpack_string argument
        argument.start_with?("gid://") ? GlobalID::Locator.locate(argument) : argument
      rescue => ex
        Plumbing.config.logger.error "!!!! #{self.class}##{__callee__} - #{argument} => #{ex}"
        argument
      end
    end
  end
end
