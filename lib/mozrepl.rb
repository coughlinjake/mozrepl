# encoding: utf-8

require 'uri'
require 'multi_json'
require 'posix-spawn'

require 'brewed'
require 'brewed/path/lock'

module MozRepl
  MOZREPL_LOCKFN = Brewed::Path.absolute_lockfn('Firefox_MozRepl.lock').freeze
end

require 'mozrepl/exceptions'

require 'mozrepl/retry'
require 'mozrepl/cond'
require 'mozrepl/xpath'

require 'mozrepl/client'
require 'mozrepl/actor'

module MozRepl
  LOCK_REPL_BASENAME = 'MozRepl.lock'.freeze

  ##
  # Optionally start Firefox if it's not already running.  Then create a new
  # connection to the REPL.
  #
  # @param parms [Hash]
  # @option parms :start_firefox  [true, false]     Start Firefox.  (Default: true)
  # @option parms :log            [Array<symbol>]   No idea...
  #
  # @return [MozRepl::Base]
  ##
  def self.new(*parms)
    repl = MozRepl::Base.new *parms
    MozRepl.__open_repls.push repl
    repl
  end

  ##
  # Acquire exclusive access to the Firefox REPL, perform whatever needs
  # to be done with Firefox in the provided block, then unlock the REPL
  # automatically.
  #
  # While the REPL is locked by this process, {MozRepl.repl_locked?}
  # will return `true`.  {MozRepl.repl_locked?} applies ONLY to the status
  # of THIS process.  If another process currently has the REPL locked,
  # {MozRepl.repl_locked?} will return `false`.
  #
  # Returns whatever is returned from the block.
  ##
  def self.lock_repl()
    rc = nil
    if MozRepl.repl_locked?
      rc = true

    elsif not block_given?
      # non-block form of lock_file returns the lock object itself.
      # store the lock object in the MozRepl class for safe-keeping.
      lock = Brewed::Path.lock_file Brewed::Path.absolute_lockfn(LOCK_REPL_BASENAME)
      MozRepl.__repl_lock lock
      rc = true

    else
      begin
        Brewed::Path.lock_file(Brewed::Path.absolute_lockfn LOCK_REPL_BASENAME) do
          MozRepl.__repl_lock
          rc = yield
        end
      ensure
        MozRepl.__repl_unlock
      end
    end

    rc
  end

  def self.release_repl()
    MozRepl.__repl_unlock if repl_locked?
  end

  ##
  # Check whether the Firefox REPL is currently locked or not.
  #
  # @!attribute [r]
  ##
  def self.repl_locked?()
    MozRepl.__repl_locked?
  end

  # @api private
  def self.__repl_locked?()
    @__repl_locked ||= false
    @__repl_locked  != false
  end

  # @api private
  def self.__repl_lock(val = true)
    @__repl_locked = val
  end

  # @api private
  def self.__repl_unlock()
    @__repl_locked.release if @__repl_locked.respond_to? :release
    @__repl_locked = false
  end

  ##
  # Terminate the provided MozRepl object, and if this MozRepl object started Firefox,
  # terminate Firefox as well.
  #
  # @param repl [MozRepl::Base]   the MozRepl::Base object to disconnect
  ##
  def self.close_repl(repl)
    r = MozRepl.__open_repls
    r.delete repl if r.include? repl
    repl.close if repl.respond_to? :close
  end

  ##
  # Generally called by Kernel.at_exit when the application terminates, close any
  # open MozRepl::Base objects.
  ##
  def self.close_all_repls()
    r = MozRepl.__reset_open_repls
    r.each { |repl| close_repl repl }
    r = nil
  end

  # @api private
  def self.__open_repls()         @__open_repls ||= []  end
  # @api private
  def self.__reset_open_repls()
    r = MozRepl.__open_repls
    @__open_repls = []
    r
  end

  ##
  ## == MozRepl::Base ==
  #
  # Base class for all MozRepl objects
  ##
  class Base
    attr_reader     :options, :client, :replid, :log
    attr_accessor   :started_ff, :_actor, :_mozrepl_lock

    def initialize(options = {})
      @options = {
          :start_firefox => true,
          :log           => %w[error],
          # :dump_log      => '__telnet_dump.log',
      }
      @options.merge! options.dup

      @log    = self.options[:log]
      @client = nil
      @replid = nil
      @started_ff = nil
      @_actor  = nil

      Log.Debug(:h1, "===STARTING MozRepl===") {
        start_firefox if self.options[:start_firefox]
        new_client
      }
    end

    ##
    # Don't terminate Firefox when we close the REPL, even if we started it.
    ##
    def cancel_kill_firefox()
      self.started_ff = false
    end

    ##
    # Returns the current {MozRepl::Actor} object for this MozRepl object.
    #
    # @note The MozRepl::Actor object isn't actually instantiated until the
    #    the first call to {MozRepl::Base#actor}.
    #
    # @return [MozRepl::Actor]
    ##
    def actor()
      self._actor = MozRepl::Actor.new :repl => self  if _actor.nil?
      _actor
    end

    ##
    # Create a new frames based Actor.
    #
    # @return [MozRepl::Actor::Frames]
    ##
    def frames_actor(options = {})
      opts = options.dup
      opts[:repl] = self
      MozRepl::Actor::Frames.new opts
    end

    # @!attribute [r]
    alias :started_firefox?   :started_ff

    ##
    # Determine if we're connected to the REPL (ie if we're connected to Firefox or not).
    #
    # @!attribute [r]
    ##
    def connected?()    client.nil? ? false : true      end

    ##
    # Disconnect the REPL and if we started Firefox, terminate Firefox.
    ##
    def close()
      unless client.nil?
        Log.Debug(:h1, "===CLOSING MozRepl===") {
          begin
            client.close
            @client = nil
            @replid = nil
          ensure
            if started_firefox?
              Log.Debug(:h2, "KILLING Firefox") {
                kill_firefox
                @started_ff = nil
              }
            end
          end
        }
      end
    end

    CMDLN_START_FF = %w[ /usr/bin/open /Applications/Firefox.app ].freeze

    ##
    # If Firefox isn't running, start it and record that we started it.
    ##
    def start_firefox()
      @started_ff = false
      Log.Debug("[START_FIREFOX]") {
        unless firefox_running?
          # start it
          Log.Debug("[starting Firefox]") {
            rc = POSIX::Spawn::Child.new *CMDLN_START_FF
            raise "executing '#{CMDLN_START_FF.join(' ')}' failed" unless rc.success?

            # give Firefox a chance to initialize
            sleep 15

            @started_ff = true

            Log.Debug "stdout", rc.out
            Log.Debug "stderr", rc.err
          }
        end
      }
    end

    CMDLN_KILL_FF = %w[ /usr/bin/osascript -s o ].freeze
    CLOSE_FF_APPLESCRIPT = 'tell application "Firefox" to quit'.freeze

    ##
    # Terminate Firefox because we're done and we're the one who started it.
    ##
    def kill_firefox()
      Log.Debug("[KILL_FIREFOX]") {
        warn "WARNING: Terminating Firefox, but we didn't start Firefox!" unless started_firefox?

        rc = POSIX::Spawn::Child.new *CMDLN_KILL_FF, :input => CLOSE_FF_APPLESCRIPT
        if not rc.success?
          raise "failed to execute AppleScript '#{CLOSE_FF_APPLESCRIPT}'"

        elsif (md = /^\d+:\d+:\s+(?<error>\w+)\s+error:/i.match(rc.out || ''))
          msg = "Detected AppleScript Error (rc: #{rc.status})\n"
          msg << "\t==SCRIPT==\n\t#{CLOSE_FF_APPLESCRIPT}\n"
          msg << "\t==STDOUT==\n\t#{rc.out || ''}\n"
          msg << "\t==STDERR==\n\t#{rc.err||'' }"
          raise msg
        end

        sleep 10

        @started_ff = false
      }
    end

    CMDLN_PS = [ '/bin/ps', '-A', '-r', '-o', 'uid pid ppid pgid %cpu pri nice time command' ].freeze

    ##
    # Check whether Firefox is running.
    # @return [true, false]
    ##
    def firefox_running?()
      rc = nil
      Log.Debug(:h2, "[FIREFOX_RUNNING?]") {
        ps = POSIX::Spawn::Child.new( {'COLUMNS' => '9999'}, *CMDLN_PS )
        raise "executing '/bin/ps' failed" unless ps.success?
        rc = %r[/Firefox\.app/Contents/MacOS/firefox].match(ps.out) ? true : false
      }
      Log.Debug :h2, "{firefox_running?} => #{rc.safe_s}"
      rc
    end

    ##
    # Close the current connection to the Firefox REPL and open a new one.
    #
    # @return [String]
    ##
    def new_client()
      Log.Debug("[NEW_CLIENT]") {
        unless client.nil?
          client.close
          @client = nil
          @replid = nil
        end

        @client = MozRepl::Client.new(options) { |msg| Log.Debug msg }
        @replid = client.replid
      }
      Log.Debug "{new_client} replid: '#{replid}'"
      replid
    end

    # @!attribute [r]
    alias :id :replid

    # @return [String]
    def to_s() "<MOZREPL ID[#{replid}]>" end

    #def inject_jquery()
    #  client.cmd %Q[#{replid}.enter(content)]
    #  client.cmd %Q[var s=document.createElement('script')]
    #  client.cmd %Q[s.src='http://code.jquery.com/jquery-1.6.1.min.js']
    #  client.cmd %Q[document.body.appendChild(s)]
    #end

  end
end

at_exit { MozRepl.close_all_repls }
