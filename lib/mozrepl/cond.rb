# encoding: utf-8

module MozRepl
  module Cond

    ##
    # Given a String, return a lambda which tests for presence of that String in any other
    # String.
    #
    #     lambda.call(other_str) => other_str or nil
    #
    # @param str [String]
    # @return [lambda]
    ##
    def self.include?(*strs)
      CondString.new strs, :include?
    end

    ##
    # Given a String, return a lambda which tests that it is the final characters of any
    # other String.
    #
    #     lambda.call(other_str) => other_str or nil
    #
    # @param str [String]
    # @return [lambda]
    ##
    def self.end_with?(*strs)
      CondString.new strs, :end_with?
    end

    ##
    # Given a pattern, return a lambda which tests whether any String matches that pattern.
    #
    #     lambda.call(str) => str or nil
    #
    # @param pat [String, Regexp]
    # @return [lambda]
    ##
    def self.matches?(pat)
      CondRegexp.new pat
    end

    ##
    # Given a block, return a lambda which calls the block.
    #
    # @return [lambda]
    ##
    def self.cond_block(&block)
      CondProc.new(&block)
    end
  end
end

module MozRepl
  module Cond

    ##
    ## == MozRepl::Cond::Base ==
    ##
    class Base
      attr_reader :match_values, :match_method, :tests, :result

      def initialize(match_values, match_method)
        @match_values = match_values
        raise ArgumentError, "expected a non-empty Array of values to match against" unless
          match_values.is_array?

        @match_method = match_method

        @result = false
        @tests  = 0
      end

      ##
      # Once the condition has been satisfied, the Cond object is essentially
      # locked.  Calling reset() clears the Cond object's status.
      ##
      def reset()
        @result = false
        @tests  = 0
      end

      ##
      # For code which expects a :call method, this :call simply invokes :test.
      ##
      def call(*params)
        self.send :test, *params
      end

      ##
      # Test a value to see whether it satisfies the condition or not.
      ##
      def test(*params)
        if result == false
          @tests += 1
          self._test *params
          self.result = false if result.nil?
        end
        result
      end

      ##
      # Was the condition satisfied?
      #
      # @note Because the object's init state is +false+ and because
      #    we canonicalize false results to +false+, the only
      #    guarantee that +test+ has been called, is when
      #    result != false.
      ##
      def success?()
        result != false
      end

      protected
      def match_values=(val)  @match_values = val end
      def result=(val)        @result = val       end
    end

    ##
    ## == MozRepl::Cond::CondString ==
    ##
    ## Conditions which test String values.
    ##
    ## Any String method may become a Cond object.
    ##
    ## @note The +CondString+ is a bit unusual in that
    ##    uses the value currently being tested to
    ##    evaluate the match value.
    ##
    ##    The reason is because the match value can be
    ##    much shorter than the test value.  This
    ##    allows, for example:
    ##
    ##        cond = CondString.new '/foo/', :include?
    ##        cond.test('/Super/cali/foo/bar/licious')
    ##
    class CondString < Base
      def initialize(match_values, match_method)
        super
        self.match_values = match_values.map { |s| s.downcase }
      end
      protected
      def _test(value)
        newvalue = (value.respond_to? :downcase) ? value.downcase : value
        unless newvalue.respond_to? match_method
          self.result = false
        else
          self.result = match_values.find { |mv| newvalue.send match_method, mv }
        end
      end
    end

    ##
    ## == MozRepl::Cond::CondRegexp ==
    ##
    ## Conditions which test values against patterns.
    ##
    class CondRegexp < Base
      def initialize(match_values)
        matchvals = match_values.map do |mv|
          (mv.is_a? Regexp) ? mv : Regexp.new(Regexp::Escape(mv), Regexp::IGNORE_CASE)
        end
        super matchvals, :match
      end
      protected
      def _test(value)
        if value.is_str?
          self.result = match_values.find { |mv| mv.match value }
        end
      end
    end

    ##
    ## == MozRepl::Cond::CondProc ==
    ##
    ## Conditions which execute a block or Proc.
    ##
    class CondProc < Base
      def initialize(&block)
        # convert the block to a proc
        blockproc = proc { |*a| block[*a] }
        super :not_used, blockproc
      end
      protected
      def _test(*parms)
        self.result = match_method.call *parms
      end
    end

  end
end
