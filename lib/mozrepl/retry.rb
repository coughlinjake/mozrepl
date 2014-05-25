# encoding: utf-8

require 'timeout'

module Retry

  TIMEOUTS = {
      :short  => 2,
      :normal => 10,
      :medium => 20,
      :long   => 30,
      :extra  => 120,
  }.freeze
  DEFAULT_TIMEOUT = :normal

  ATTEMPTS = {
      :few    => 5,
      :normal => 10,
      :many   => 20,
  }.freeze
  DEFAULT_ATTEMPTS = :normal

  PAUSES = {
      :short        => 0.5,
      :normal       => 1,
      :above_normal => 5,
      :long         => 10,
      :progressive => [ 0.5, 0.5, 1, 1, 2, 2, 5, 5 ],
  }.freeze
  DEFAULT_PAUSE = :progressive

  ##
  # Retry until either a condition is true or a timeout occurs or a minimum
  # number of attempts have been made.
  #
  # retry_until yields to its block.  If the block returns a true value,
  # retry_until returns that value.  Otherwise, retry_until sleeps a bit
  # and then yields to its block again.
  #
  # @param options [Hash]
  # @option options :cond     [MozRepl::Cond]             (Optional) retry until this MozRepl::Cond returns true
  # @option options :args     [Object, Array<Object>]     (Optional) args that will be yielded to the block
  # @option options :timeout  [Symbol, Integer, Float]    (Optional) max time to allow for success before failing
  # @option options :attempts [Integer]                   (Optional) number of attempts to make before failing
  # @option options :pause    [Symbol, Integer]           (Optional) pause time between attempts
  #
  # @return the first non-nil, non-false value returned from the block
  ##
  def retry_until(options = {})
    timeout   = options[:timeout] || DEFAULT_TIMEOUT
    timeout   = TIMEOUTS[timeout] if timeout.is_str?
    raise ArgumentError, "invalid timeout: '#{timeout}'" unless
        timeout.is_a?(Integer) or timeout.is_a?(Float)

    attempts  = options[:attempts] || DEFAULT_ATTEMPTS
    attempts  = ATTEMPTS[attempts] if attempts.is_str?
    raise ArgumentError, "attempts must be >= 1" unless attempts >= 1

    pause_opt = pause = options[:pause] || DEFAULT_PAUSE
    pause     = PAUSES[pause] if pause.is_str?
    raise ArgumentError, "invalid pause: #{pause.inspect}" unless
        pause.is_a?(Integer) or pause.is_a?(Float) or pause.is_a?(Array)

    if attempts == 1
      pause_opt = pause = 0
    elsif pause.is_a?(Array) and pause.length <= attempts
      pause.push *([pause[-1]] * (attempts - pause.length))
    end

    cond = options[:cond]
    unless block_given?
      raise ArgumentError, "either provide a block to execute or a MozRepl::Cond" unless
          cond.is_a? MozRepl::Cond::Base
    end

    # these args are yielded to the block
    args = options[:args] || []

    rc = nil
    Log.Debug("[RETRY_UNTIL]", :timeout => timeout, :attempts => attempts, :pause => pause_opt) {
      begin
        Timeout::timeout(timeout) do

          (0..attempts).each do |attempt|
            Log.Debug "ATTEMPT #{attempt}"

            if block_given?
              Log.Debug("[yielding to block]") {
                rc = yield *args
                if rc == false or rc == nil
                  Log.Debug "\tblock returned FAILED result"
                  rc = nil
                else
                  Log.Debug "\tblock returned SUCCESS result"
                  break
                end
              }
            end

            break unless rc.nil?

            if cond != nil
              Log.Debug("[calling cond]") {
                rc = cond.test
                if rc == false or rc == nil
                  Log.Debug "\tcond returned FAILED result"
                  rc = nil
                else
                  Log.Debug "\tcond returned SUCCESS result"
                  break
                end
              }
            end

            break unless rc.nil?

            p = pause.is_a?(Array) ? pause[attempt] : pause
            Log.Debug "Attempt #{attempt} FAILED: sleep #{p}", rc
            sleep p
          end
        end

      rescue Timeout::Error
        Log.Debug "**TIMER EXPIRED!**"
        rc = nil
      end
    }

    Log.Debug "{retry_until} :=>", rc
    rc
  end

end
