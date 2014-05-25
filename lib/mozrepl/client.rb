# encoding: utf-8

require 'base64'
require 'net/telnet'

require 'multi_json'

module MozRepl

  ##
  ## == MozRepl::EvalRC ==
  #
  # Results of an REPL evaluation.
  #
  # @note The properties passed into `EvalRC.new` are :status, :message, :results.
  #    These properties exactly match the object which the JavaScript running in
  #    the REPL return.
  ##
  class EvalRC
    attr_reader :status, :message, :results

    def initialize(props = {})
      @status  = props[:status]
      @status  = @status.to_s.upcase.to_sym if @status.is_str?

      @message = props[:message]
      @results = props[:result]

      # if the status is :OK but there are no results, then
      # set the results to true.  the assumption is that
      # status == :OK means that the REPL called rc_ok() rather
      # than rc_fail().
      #@results ||= true if @status == :OK
    end

    def ok?() status == :OK end

    ##
    # Shortcut for creating an EvalRC for a REPL call which encountered an error.
    #
    # @param msg [Array<String>]
    # @return [EvalRC]
    ##
    def self.error(*msg)
      self.class.new :status => :ERROR, :message => msg.join('')
    end

  end

  ##
  ## == MozRepl::Client ==
  ##
  class Client < Net::Telnet
    include ParamUtils

    MATCH     = 'Match'.freeze
    STRING    = 'String'.freeze

    CMD_SEP   = "\n--end-remote-input\n".freeze

    PROMPT    = /repl\d*>\s/.freeze
    REPL_INIT = /==REPL IS( NOT)? INITIALIZED==/.freeze

    attr_accessor :host, :port, :timeout
    attr_accessor :binmode, :buzsize
    attr_accessor :replid, :prompt
    attr_accessor :output_log, :dump_log
    attr_accessor :log_repl_calls
    alias   :log_repl_calls?    :log_repl_calls

    ##
    # Connect to the REPL.
    #
    # @param props [Hash]
    # @option props :host [String]
    # @option props :port [Integer]
    # @option props :timeout [Integer]
    ##
    def initialize(props = {}, &block)
      p = {
          :host       => '127.0.0.1',
          :port       => 4242,
          :timeout    => 1000,
          :binmode    => true,
          :bufsize    => 10240000,
          :log_repl_calls => false,
          :output_log     => nil,
          :dump_log       => nil,
      }.merge! props

      self.update_from_hash! p

      telnetopts = {
          'Host'     => host,
          'Port'     => port,
          'Timeout'  => timeout,
          'Binmode'  => binmode,
      }
      telnetopts['Output_log'] = output_log if output_log.is_str?
      telnetopts['Dump_log']   = dump_log   if dump_log.is_str?

      Log.Debug "Connecting to '#{host}:#{port}..."
      begin
        super telnetopts, &block
      rescue Errno::ECONNREFUSED
        raise NoFirefox
      end

      data = waitfor PROMPT

      @replid = 'repl'
      /(?<replid>repl\d*)>\s/.match(data) { |m| @replid = m[:replid] if m[:replid].is_str? }
      Log.Debug "\tREPL ID: '#{replid}'"

      @prompt = Regexp.new replid+'>\s'

      # the REPL needs to be initialized.  see the notes in init.js (ie js/REPL.js) with
      # regard to initializing the REPL.  we'll make 2 attempts then you'll just have to
      # start the fucking browser yourself and keep the fucking window open!!!
      Log.Debug(:h1, "[INITIALIZE REPL]") {
        init_cmd = "#{replid}.repl_initialize(content)"

        repl_is_init = _cmd init_cmd, :wait_for => REPL_INIT
        #Log.Debug "REPL INIT RESPONSE: |#{repl_is_init}|"

        if repl_is_init.include? 'NOT'
          # REPL should be opening a new window now so wait and try again.
          sleep 2

          repl_is_init = _cmd init_cmd, :wait_for => REPL_INIT
          # Log.Debug "2nd REPL INIT RESPONSE: |#{repl_is_init}|"

          raise "REPL FAILS TO INITIALIZE" if repl_is_init.include? 'NOT'
        end
      }
    end

    def to_s() "<MOZREPL::CLIENT ID[#{replid}] HOST[#{host}:#{port}]>" end

    alias_method :_old_cmd, :cmd

    ##
    # Execute a REPL API command which returns a simple, primitive result.
    #
    # Returns the simple, primitive result directly.
    #
    # @param command [String]
    #
    # @param options [Hash]
    # @option options :wait_for [Regexp]
    #
    # @return [String]
    ##
    def cmd(command, options = {})
      if options[:wait_for]
        _cmd command, MATCH => options[:wait_for]
      else
        _cmd command
      end
    end

    ##
    # Execute a REPL API command which returns its results by calling
    # REPL.rc_ok() or REPL.rc_fail().
    #
    # @param command [String]
    #    a string of Javascript which executes within the REPL
    #
    # @return [EvalRC]
    ##
    SPACE = ' '.freeze
    def json_cmd(command)
      # convert all newline characters in the command to single space
      # so the entire command is a single line.  then we need to
      # wait until we have the entire JSON response.
      output = _cmd command.gsub(/[\r\n]/, SPACE), MATCH => /==END-JSON==\n/

      rc = nil
      unless output.is_str?
        rc = EvalRC.error 'json_cmd: expected String from _cmd'
      else
        output.match( /==BEGIN-JSON==\s*(?>(?<json>.+?)\n+==END-JSON==)/ ) do |m|
          rc = EvalRC.new MultiJson.load(m[:json], :symbolize_keys => true)
        end
      end

      rc
    end

    ##
    # Send the full command across the telnet connection to the JS env and wait for
    # the response.
    #
    # @param command [String]
    #    the text string that the remote REPL will evaluate
    #
    # @param options [Hash]
    # @option options :wait_for [Regexp]
    #    (Optional) continue reading the response until the provided pattern
    #    matches
    ##
    #def multiline_cmd(command, options = {})
    #  _cmd [
    #           %Q[#{replid}.pushenv('printPrompt', 'inputMode'); ],
    #           %Q[#{replid}.setenv('printPrompt', false); ],
    #           %Q[#{replid}.setenv('inputMode', 'multiline');undefined;\n]
    #       ].join('')
    #  sleep 0.5
    #  unless options[:wait_for]
    #    _cmd (command.rstrip + cmd_sep)
    #  else
    #    # wait until we see something very specific in the data we recv back
    #    _cmd (command.rstrip + cmd_sep), 'Match' => options[:wait_for]
    #    _cmd ('' + cmd_sep)
    #  end
    #  _cmd [ %Q[#{replid}.popenv('inputMode', 'printPrompt');undefined;\n], CMD_SEP ].join('')
    #end

    private

    ##
    # Send a command to the repl and recv the result.
    ##
    EMPTY_STR    = ''.freeze
    LOG_CLT_SEND = '[CLIENT.COMMAND >>] '.freeze
    LOG_CLT_RECV = '{CLIENT.COMMAND <<} => '.freeze
    def _cmd(command, options = {}, &blk)
      opt = {
          MATCH  => @prompt,
          STRING => command,
      }.merge! options

      Log.Debug LOG_CLT_SEND, command if log_repl_calls?

      # TODO|don't bother with the specific repl prompt which we happened to
      # to get by chance.  just write a general @prompt regexp which matches
      # ANY repl promnpt and eliminate the asinine Hash!
      recv = _old_cmd opt, &blk

      # TODO|technically we should be stripping opt['Match'], but
      # for this application, stripping the repl prompt doesn't
      # cause any problems.
      recv.gsub! @prompt, EMPTY_STR
      Log.Debug LOG_CLT_RECV, recv     if log_repl_calls?

      recv
    end
  end
end
