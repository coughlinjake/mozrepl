# encoding: utf-8

# mozrepl/actor/js.rb
#
# This file contains source code for the class MozRepl::Actor::Base.
# MozRepl::Actor::Base is split among several files to make the code
# easier to navigate.
#
# The methods here:
#   * generate strings of JavaScript
#   * add JavaScript to the code accumulator
#   * compile the accumulator into an executable block
#   * marshall the executable block to/from the REPL

module MozRepl
  module Actor

    class Base

      DEFAULT_EXEC_TIMEOUT = 30.freeze

      class JsValue
        attr_reader :js_value
        def initialize(js_value)
          @js_value = js_value
        end
        def to_s() js_value end
      end

      ##
      # Declare a JavaScript value or a block of JavaScript code in order to protect
      # it from being marshalled.
      #
      # @param jsval [String]
      # @return [JsValue]
      ##
      def js_value(jsval) JsValue.new jsval end
      alias :js_code    :js_value

      ##
      # Marshal the provided object.
      #
      # Ruby types are marshalled to JSON strings.
      # JavaScript code and values are passed thru unaltered.
      #
      # @param obj [String, JsValue]
      # @return [String]
      ##
      def marshal(obj)    (obj.respond_to? :js_value) ? obj.js_value : MultiJson.dump(obj) end

      COLON    = ';'.freeze
      COLON_NL = ";\n".freeze
      COMMA    = ','.freeze

      ##
      # Constructs a parameter list for a generated JavaScript function call.
      #
      # Most parameters for REPL functions pass "data" into the REPL function.
      # On this side, that data is in Ruby objects; on the REPL side, that data
      # must be in JavaScript objects.  js_parms performs the marshalling of
      # Ruby objects to JavaScript objects.
      #
      # Frequently, we also need to pass "code" into a REPL function.  Code
      # originates on the Ruby side as a String containing JavaScript.
      #
      # The REPL simply evaluates whatever we hand it.  So marshalling data merely
      # requires putting the data into a form which evaluates to the data objects.
      # The same holds true for code.
      #
      # @note The call signature for `js_params` creates a constraint for any
      #    REPL function which will be called via `js_params`.  The REPL
      #    function's marshalled parameters are grouped together and precedes
      #    the group of unmarshalled parameters.
      #
      # @param params [Object, Array<Object>, []]
      #    either a single Ruby object or an Array of Ruby objects that must be marshalled
      #    Ruby types to JavaScript types.
      #
      # @note If the parameters consist entirely of unmarshalled parameters,
      #    simply pass [] as the first parameter to `js_params`.
      ##
      def js_parms(params)          params.map { |p| marshal p }.join(COMMA)            end

      def js_repl(meth, *args)      js_value %Q|repl.#{meth.to_s}( #{js_parms(args)} )| end

      def js_json_parms(args = {})
        parms =
            args.map.each { |var, val| %Q|"#{var.to_s}": #{marshal val}| }
        js_value %Q|{ #{parms.join(COMMA) } }|
      end

      ##
      # Generate JavaScript to assign a value to a JavaScript variable.
      #
      # @param pairs [Hash]
      #     a Hash containing a single key, value pair.
      #     The key becomes the JavaScript variable name and the value is marshalled
      #     so it can be a JavaScript expression.
      #
      # @return [String]
      ##
      def js_set(pairs = {})
         raise ArgumentError, "only a single variable is supported" if pairs.keys.length > 1
        pairs.map.each { |var, expr| js_value %Q|#{var.to_s} = #{marshal expr}| }.join(COLON)
      end

      def js_get(var)               js_value %Q|#{var.to_s}|                      end

      def js_return(expr)           js_value %Q|return #{marshal expr}|           end

      def js_repl_rc_ok(expr)       js_value %Q|repl.rc_ok( #{marshal expr} )|    end
      def js_repl_rc_fail(expr)     js_value %Q|repl.rc_fail( #{marshal expr} )|  end

      ##
      # Wrap the provided JavaScript statements within a simple function.
      ##
      def js_func(*jsstmts)         js_value %Q|function(rc) { #{jsstmts.join(COLON)}; }|         end

      def js_on_succ(expr)          js_value %Q|function(rc) { repl.rc_ok( #{marshal expr} ); }|  end

      ##
      # When strings of JavaScript are provided, each string has ';' appended to it
      # and is then appended to the current accumulated code.
      #
      # With no parameters, all of the current accumulated code since the last
      # `compile` is returned as an Array of String.
      #
      # @param jsstmts [Array<String>]
      #    an Array containing strings of JS code.
      #
      # @return [Array<String>, self]
      #    when `jsstmts` is an empty Array, returns the current accumulated code
      #    as an Array of String.
      #
      #    when `jsstmts` is NOT empty, returns self
      ##
      def code(*jsstmts)
        if jsstmts.length == 0
          _code
        else
          # the JS statements passed in should have already been marshalled.
          # consequently, there should only be Strings containing JS code.
          # however, call .to_s() on each just in case any JsValue objects
          # were passed in.
          _code.concat jsstmts.map { |js| js.to_s + COLON_NL }
          self
        end
      end

      ##
      # Code the JS which assigns the result of `jsexpr` to the variable `rc`.
      #
      # @param jsexpr [String]
      #    String containing a JS expression
      #
      # @return [void]
      ##
      def code_rc_set(expr)
        code js_set(:rc => expr)
      end

      ##
      # Convenience method which calls MozRepl::Actor::Base#code followed by
      # MozRepl::Actor::Base#compile
      #
      # @param jsstmts [Array<String>]
      #
      # @return [void]
      ##
      def compile_code(*jsstmts)
        code *jsstmts
        compile
      end

      ##
      # Compile all of the accumulated code and clear the code accumulator.
      #
      # @note At least one of the accumulated code statements MUST set the
      #    variable `rc`.  Otherwise, no value will be returned when this
      #    block of accumulated code is executed.
      #
      # The compiled code can be retrieved by calling MozRepl::Actor::Base#_compiled.
      # But there should be no need to do that because once `compile` has been called,
      # MozRepl::Actor::Base#exec can be called to execute the compiled code.
      #
      # @return [void]
      ##
      def compile()
        self._compiled = <<"JAVASCRIPT"
(function(repl) {
  try {
    var rc;
    #{code.join(' ')}
    repl.rc_ok(rc);
  } catch(e) {
    repl.rc_fail(e.name, e.message ? e.message : e);
  };
})(#{replid});
JAVASCRIPT
        self._code = []
      end

      ##
      # Compile the accumulated code as a callback transaction.
      #
      # Within the REPL, a callback transaction executes a task asynchronously.
      # The task is initiated and a callback function is provided as one of the
      # task's parameters.  After the task is initiated, the current execution
      # thread of the REPL "returns".  Later, on another execution thread, the
      # task completes and invokes the callback.
      #
      # The client "executes" the task synchronously.
      #
      # @note SIDE EFFECT: The accumulated code is compiled into a private
      #    instance variable (replacing whatever compilation was already
      #    there).  The code accumulator is then **emptied**, making it ready
      #    to accumulate code for the next task.
      #
      #    The compiled code remains in the private instance variable until
      #    another compile method is called.
      #
      # @param args [Hash]
      #
      # @option args :cond         [String]
      #    (Optional) JS anon function which corresponds to the `retry_until` cond param
      #
      # @option args :xpath        [String]
      # @option args :sleep        [Integer]
      # @option args :max_attempts [Integer]
      #
      # @option args :cond         [String]
      # @option args :on_succ      [String]
      # @option args :on_fail      [String]
      #    (Optional) correspond to the `retry_until` params with the same name
      #
      # @return [void]
      ##
      def compile_callback(meth, args = {})
        code( js_repl meth, js_json_parms(args) )

        self._compiled = <<"JAVASCRIPT"
(function(repl) {
  try {
    #{code.join(' ')}
  } catch(e) {
    repl.rc_fail(e.name, e.message ? e.message : e);
  };
})(#{replid});
JAVASCRIPT

        self._code = []
      end

      EVALRC   = 'EvalRC:'.freeze
      COMPILED = 'COMPILED: '.freeze

      ##
      # Execute the compiled JS in the REPL and retrieve the result.
      #
      # After the result is received, exec verifies that the marshalling
      # between Ruby and the REPL succeeded.  If the REPL calling mechanism failed,
      # returns nil.
      #
      # @note `exec` provides no method for passing parameters into the compiled
      #   JavaScript.  Function parameters must have provided during compilation.
      #
      # @note If an error occurs, `exec` will pass `log_error_props` AS IS to
      #   the log.  This allows the caller to provide any needed identification for
      #   the compiled JavaScript.
      #
      # @return [EvalRC]
      ##
      def exec(options = {})
        timeout = options[:timeout] || DEFAULT_EXEC_TIMEOUT

        rc = nil
        Log.Debug(:h3, "[#{self.class.to_s}.EXEC]") {

          Log.Debug COMPILED, _compiled if log_compiled?

          begin
            Timeout::timeout(timeout) do

              rc = repl.client.json_cmd _compiled
              Log.Debug EVALRC, rc

              if call_error? rc
                Log.Fail "FAILED: #{self.class.to_s}.exec", rc
                rc = nil
              else
                rc = rc.results
              end
            end

          rescue Timeout::Error
            Log.Debug "**TIMER EXPIRED!** #{self.class.to_s}#exec FAILED!"
            rc = nil
          end

        }
        Log.Debug "{#{self.class.to_s}.exec} :=> ", rc
        rc
      end

      ##
      # Compile the accumulated code then execute it.
      #
      # @return [EvalRC]
      ##
      def compile_exec()
        compile
        exec
      end

      ##
      # Determine if the REPL was called and a result was returned.
      ##
      def call_error?(rc) (rc.respond_to?(:ok?) and rc.ok?) ? false : true end
    end

  end
end
