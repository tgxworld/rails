module ActionDispatch
  class RackTimer
    def initialize(app)
      @app = app
      self.extend(Timer)
    end

    def call(env)
      @app.call(env)
    end

    module Timer
      def self.extended(object)
        object.singleton_class.class_eval do
          alias_method :call_without_timing, :call
          alias_method :call, :call_with_timing
          public :call
        end

        object.instance_eval do
          recursive_timer

          @total_time = 0
        end
      end

      def extended?
        true
      end

      def recursive_timer
        return if @app.nil?
        return if @app.respond_to?(:extended?)
        return unless @app.respond_to?(:call)
        @app.extend(Timer)
      end

      private

      def call_with_timing(env)
        time_before = Time.now
        result = call_without_timing(env)
        time_after = Time.now - time_before

        if time_inner = env['rack-timer.time']
          time_self = time_after - time_inner
        else
          time_self = time_after
        end

        @total_time += time_self

        log("#{self.class.name} took #{time_self}s (#{@total_time}s)")

        env['rack-timer.time'] = time_after
        result
      end


      def log(message)
        $stderr.puts(message)
      end
    end
  end
end
