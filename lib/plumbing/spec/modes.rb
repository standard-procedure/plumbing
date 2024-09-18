module Plumbing
  module Spec
    def self.modes(inline: true, async: true, threaded: true, &)
      Plumbing.configure(mode: :inline, &) if inline
      Sync { Plumbing.configure(mode: :async, &) } if async
      Plumbing.configure(mode: thread_mode, &) if threaded
    end

    def self.thread_mode
      defined?(::Rails) ? :threaded_rails : :threaded
    end
    private_class_method :thread_mode
  end
end
