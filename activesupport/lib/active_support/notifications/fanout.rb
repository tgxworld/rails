require 'mutex_m'
require 'thread_safe'

module ActiveSupport
  module Notifications
    # This is a default queue implementation that ships with Notifications.
    # It just pushes events to all registered log subscribers.
    #
    # This class is thread safe. All methods are reentrant.
    class Fanout
      include Mutex_m

      def initialize
        @listeners_for = ThreadSafe::Cache.new
        @all_listeners = ThreadSafe::Array.new
        @regex_listeners = ThreadSafe::Array.new
        super
      end

      def subscribe(pattern = nil, block = Proc.new)
        subscriber = Subscribers.new pattern, block
        synchronize do
          case pattern
          when String
            @listeners_for[pattern] ||= []
            @listeners_for[pattern] << subscriber
          when Regexp
            @regex_listeners << subscriber
          else
            @all_listeners << subscriber
          end
        end
        subscriber
      end

      def unsubscribe(subscriber_or_name)
        synchronize do
          case subscriber_or_name
          when String
            @listeners_for[subscriber_or_name].clear
          when Subscribers::Evented, Subscribers::Timed
            @listeners_for[subscriber_or_name.pattern].delete(subscriber_or_name)
          when Subscribers::AllMessages
            @all_listeners.delete(subscriber_or_name)
          end
        end
      end

      def start(name, id, payload)
        listeners_for(name).each { |s| s.start(name, id, payload) }
      end

      def finish(name, id, payload)
        listeners_for(name).each { |s| s.finish(name, id, payload) }
      end

      def publish(name, *args)
        listeners_for(name).each { |s| s.publish(name, *args) }
      end

      def listeners_for(name)
        synchronize do
          @regex_listeners.select! { |x| x.matches?(name) }

          if @listeners_for[name].nil?
            @all_listeners + @regex_listeners
          else
            @listeners_for[name] + @all_listeners + @regex_listeners
          end
        end
      end

      def listening?(name)
        listeners_for(name).any?
      end

      # This is a sync queue, so there is no waiting.
      def wait
      end

      module Subscribers # :nodoc:
        def self.new(pattern, listener)
          if listener.respond_to?(:start) and listener.respond_to?(:finish)
            subscriber = Evented.new pattern, listener
          else
            subscriber = Timed.new pattern, listener
          end

          unless pattern
            AllMessages.new(subscriber)
          else
            subscriber
          end
        end

        class Evented #:nodoc:
          attr_reader :pattern

          def initialize(pattern, delegate)
            @pattern = pattern
            @delegate = delegate
            @can_publish = delegate.respond_to?(:publish)
          end

          def publish(name, *args)
            if @can_publish
              @delegate.publish name, *args
            end
          end

          def start(name, id, payload)
            @delegate.start name, id, payload
          end

          def finish(name, id, payload)
            @delegate.finish name, id, payload
          end

          def subscribed_to?(name)
            @pattern === name
          end

          def matches?(name)
            @pattern && @pattern === name
          end
        end

        class Timed < Evented
          attr_reader :pattern

          def publish(name, *args)
            @delegate.call name, *args
          end

          def start(name, id, payload)
            timestack = Thread.current[:_timestack] ||= []
            timestack.push Time.now
          end

          def finish(name, id, payload)
            timestack = Thread.current[:_timestack]
            started = timestack.pop
            @delegate.call(name, started, Time.now, id, payload)
          end
        end

        class AllMessages # :nodoc:
          def initialize(delegate)
            @delegate = delegate
          end

          def start(name, id, payload)
            @delegate.start name, id, payload
          end

          def finish(name, id, payload)
            @delegate.finish name, id, payload
          end

          def publish(name, *args)
            @delegate.publish name, *args
          end

          def subscribed_to?(name)
            true
          end

          alias :matches? :===
        end
      end
    end
  end
end
