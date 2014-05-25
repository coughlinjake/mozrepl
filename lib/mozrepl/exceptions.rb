# encoding: utf-8

require 'exceptions'

module MozRepl

  class FatalError < StandardError;         end
  class RetryableError < StandardError;     end
  class RestartableError < StandardError;   end

  # ======================
  # == FATAL exceptions ==
  # ======================

  class NoFirefox         < FatalError; end           # the Firefox running the REPL doesn't seem to be running.
  class InvalidParams     < FatalError; end           # ArgumentError except it responds to :fatal?
  class NoCredentials     < FatalError; end           # website demanded authentication and we had none to provide.
  class MaxAttempts       < FatalError; end           # the maximum number of attempts has been exceeded

  class NoFrameURL        < FatalError; end           # MozRepl::Actor::Frame requires a frame_url for this action
  class NoPageURL         < FatalError; end

  # ==========================
  # == NON-FATAL exceptions ==
  # ==========================

  class LockReplFirst < RetryableError
    DESC = 'The REPL must be locked before any REPL actions'
  end
  class NavError          < RetryableError; end
  class ElementMissing    < RetryableError; end
  class NoCookies         < RetryableError; end

  # ============================
  # == RESTARTABLE exceptions ==
  # ============================
  # Exceptions which should be re-attempted the next time the program is executed.


  # ==========================
  # == RETRYABLE exceptions ==
  # ==========================
  # Exceptions that are the result of temporary failures or glitches.
  #
  # The operation which raised the exception should be retried after a
  # brief period of time.
  class ExternalAppFailed < RetryableError; end

  # ==================
  # == API failures ==
  # ==================
  class ApiError < FatalError; end

  def self.error(message)
    raise MozRepl::Exception.new(message)
  end

end
