# frozen_string_literal: true

# :markup: markdown

require "action_dispatch/journey/nfa/dot"

module ActionDispatch
  module Journey # :nodoc:
    module GTG # :nodoc:
      class TransitionTable # :nodoc:
        include Journey::NFA::Dot

        attr_reader :memos

        DEFAULT_EXP = /[^.\/?]+/

        def initialize
          @stdparam_states = {}
          @regexp_states   = {}
          @string_states   = {}
          @accepting       = {}
          @memos           = Hash.new { |h, k| h[k] = [] }
        end

        def add_accepting(state)
          @accepting[state] = true
        end

        def accepting_states
          @accepting.keys
        end

        def accepting?(state)
          @accepting[state]
        end

        def add_memo(idx, memo)
          @memos[idx] << memo
        end

        def memo(idx)
          @memos[idx]
        end

        def eclosure(t)
          Array(t)
        end

        def move(current_states, _full_string, token, start_index, token_matches_default)
          return [] if current_states.empty?

          next_states = []
          seen_states = {}
          pending_states = {}

          index = 0
          while index < current_states.size
            state = current_states[index]
            previous_start = current_states[index + 1]

            if previous_start.nil?
              if token_matches_default && (next_state = @stdparam_states[state])
                add_state(next_states: next_states, seen_states: seen_states, state: next_state)
              end

              if (transitions = @string_states[state]) && (next_state = transitions[token])
                add_state(next_states: next_states, seen_states: seen_states, state: next_state)
              end
            end

            if (transitions = @regexp_states[state])
              transitions.each do |regexp, destination_state|
                next if destination_state.nil?
                if previous_start || regexp.match?(token)
                  add_state(
                    next_states: next_states,
                    seen_states: seen_states,
                    state: destination_state,
                  )
                end
              end

              if !pending_states.key?(state)
                pending_states[state] = true
                next_states << state << (previous_start || start_index)
              end
            end

            index += 2
          end

          next_states
        end

        def as_json(options = nil)
          simple_regexp = Hash.new { |h, k| h[k] = {} }

          @regexp_states.each do |from, hash|
            hash.each do |re, to|
              simple_regexp[from][re.source] = to
            end
          end

          {
            regexp_states:   simple_regexp.stringify_keys,
            string_states:   @string_states.stringify_keys,
            stdparam_states: @stdparam_states.stringify_keys,
            accepting:       @accepting.stringify_keys
          }
        end

        def to_svg
          svg = IO.popen("dot -Tsvg", "w+") { |f|
            f.write(to_dot)
            f.close_write
            f.readlines
          }
          3.times { svg.shift }
          svg.join.sub(/width="[^"]*"/, "").sub(/height="[^"]*"/, "")
        end

        def visualizer(paths, title = "FSM")
          viz_dir   = File.join __dir__, "..", "visualizer"
          fsm_js    = File.read File.join(viz_dir, "fsm.js")
          fsm_css   = File.read File.join(viz_dir, "fsm.css")
          erb       = File.read File.join(viz_dir, "index.html.erb")
          states    = "function tt() { return #{to_json}; }"

          fun_routes = paths.sample(3).map do |ast|
            ast.filter_map { |n|
              case n
              when Nodes::Symbol
                case n.left
                when ":id" then rand(100).to_s
                when ":format" then %w{ xml json }.sample
                else
                  "omg"
                end
              when Nodes::Terminal then n.symbol
              else
                nil
              end
            }.join
          end

          stylesheets = [fsm_css]
          svg         = to_svg
          javascripts = [states, fsm_js]

          fun_routes  = fun_routes
          stylesheets = stylesheets
          svg         = svg
          javascripts = javascripts

          require "erb"
          template = ERB.new erb
          template.result(binding)
        end

        def []=(from, to, sym)
          case sym
          when String, Symbol
            to_mapping = @string_states[from] ||= {}
            # account for symbols in the constraints the same as strings
            to_mapping[sym.to_s] = to
          when Regexp
            if sym == DEFAULT_EXP
              @stdparam_states[from] = to
            else
              to_mapping = @regexp_states[from] ||= {}
              # we must match the whole string to a token boundary
              to_mapping[/\A#{sym}\Z/] = to
            end
          else
            raise ArgumentError, "unknown symbol: %s" % sym.class
          end
        end

        def states
          ss = @string_states.keys + @string_states.values.flat_map(&:values)
          ps = @stdparam_states.keys + @stdparam_states.values
          rs = @regexp_states.keys + @regexp_states.values.flat_map(&:values)
          (ss + ps + rs).uniq
        end

        def transitions
          # double escaped because dot evaluates escapes
          default_exp_anchored = "\\\\A#{DEFAULT_EXP.source}\\\\Z"

          @string_states.flat_map { |from, hash|
            hash.map { |s, to| [from, s, to] }
          } + @stdparam_states.map { |from, to|
            [from, default_exp_anchored, to]
          } + @regexp_states.flat_map { |from, hash|
            hash.map { |r, to| [from, r.source.gsub("\\") { "\\\\" }, to] }
          }
        end

        private
          def add_state(next_states:, seen_states:, state:)
            return if seen_states.key?(state)

            seen_states[state] = true
            next_states << state << nil
          end
      end
    end
  end
end
