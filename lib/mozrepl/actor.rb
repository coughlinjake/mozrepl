# encoding: utf-8

module MozRepl
  module Actor

    def self.new(*params)
      MozRepl::Actor::Base.new *params
    end

    class Base
      include Retry

      attr_reader     :repl
      attr_accessor   :replid, :_code, :_compiled
      attr_accessor   :log_compiled

      alias           :log_compiled?  :log_compiled

      def initialize(properties = {})
        @repl = properties[:repl]
        raise ArgumentError, ":repl is a required parameter" unless
            repl.is_a? MozRepl::Base

        @log_compiled = properties[:log_compiled] || false
        @replid       = repl.id
        @_code        = []
        @_compiled    = nil
      end

      def new_client()
        self.replid = repl.new_client
      end

      def _check_repl_lock()
        raise LockReplFirst,
              "The Firefox REPL must be locked before performing any actions with it." unless
            MozRepl.repl_locked?
      end

    end
  end
end

require 'mozrepl/actor/js'

module MozRepl
  module Actor
    class Base
      READY_STATE_COMPLETE = 'complete'.freeze

      ##
      # get_repl_log()
      ##
      def get_repl_log()
        rc = nil
        Log.Debug(:h3, "[#{self.class.to_s}.GET_REPL_LOG]") {
          _check_repl_lock
          compile_callback :GetLog
          rc = exec
          Log.Debug(:h3, "===REPL LOG===") {
            Log.Debug rc
          }
        }
      end

      ##
      # Wait for the page to "finish" loading by examining the value of
      # +doc.readyState+ until its value is +complete+.
      #
      # Returns +true+ if +doc.readyState+ returns "complete".  Otherwise
      # returns +false+.
      #
      # @return [true, false]
      ##
      def wait_page_load()
        rc = nil
        Log.Debug(:h5, "[#{self.class.to_s}.WAIT_PAGE_LOAD]") {
          _check_repl_lock
          _compile_wait_page_load
          rc = exec
          rc = (rc.is_str? and rc.include?(READY_STATE_COMPLETE)) ? true : false
        }
        Log.Debug "{#{self.class.to_s}.wait_page_load} :=> #{rc.safe_s}"
        rc
      end
      def _compile_wait_page_load()
        compile_callback :retry_until,
                         :cond => js_code( %Q|function() {
                                                   var rc = repl.get_document().readyState;
                                                   return (rc === 'complete') ? rc : null;
                                                 }| )
      end

      ##
      # Navigate the browser to the provided URL and wait for the
      # document's +readyState+ to be +complete+.
      #
      # @param url [String]
      #
      # @param options [Hash]
      # @option options :pause [Integer]
      #    (Optional) number of seconds to sleep before continuing
      #
      # @return [true, false]
      ##
      def goto_url(url, options = {})
        rc = nil
        Log.Debug(:h4, "[#{self.class.to_s}.GOTO_URL '#{url}']") {
          _check_repl_lock

          compile_callback :goto_url, :url => url.to_s

          rc = exec
          unless rc.is_str?
            rc = nil
          else
            rc = wait_page_load
            if rc != true
              rc = nil
            elsif options[:pause].is_a?(Integer) and options[:pause] > 0
              sleep options[:pause]
            end
          end
        }
        Log.Debug "{#{self.class.to_s}.goto_url} :=> #{rc.safe_s}"
        rc
      end

      ##
      # Retrieve the URL of the current page.
      #
      # When no parameters are provided, the page's URL is returned immediately.
      #
      # @note Sometimes loading one URL redirects to a different URL very quickly
      #     (to perform a logon), and then either stays at the new URL
      #     (because no credentials are available) or redirects BACK to the
      #     original URL (because saved credentials were correct).
      #
      #     Currently, the REPL doesn't install any handlers which allow it to
      #     track when it navigates away from the current page, for whatever reason.
      #     Even when we initiate the navigation, the browser may be redirected any
      #     number of times -- usually to implement authentication.
      #
      # Since navigating to a page may redirect several times before finally
      # settling on a particular page (perhaps the page we navigated to if we're
      # already logged in, perhaps a login page if the server demands we log in),
      # which page URL we get can be impossible to determine.
      #
      # If we know the possible landing pages, the redirection issue can be handled
      # with the `:wait_for` parameter.  The allowed types of `:wait_for`:
      #
      # * `String` => a `Regexp` will be constructed from the `String`
      # * `Regexp` => `get_url` won't return the page URL matches the regexp.
      # * `Proc`   => page URLs will be passed to the `:call` method until it returns `true`
      #
      # @param opts [Hash]
      # @option opts :wait_for [String, Regexp, Proc]
      # @option opts :attempts [Integer]
      # @option opts :pause [Integer, Float]
      #
      # @return [nil, String]
      ##
      def get_url(opts = {})
        url = nil
        Log.Debug(:h4, "[#{self.class.to_s}.GET_URL]") {
          _check_repl_lock

          _compile_get_url

          if opts.empty?
            # no options so get the URL and return it
            url = exec

          else
            options = {
                :attempts => 15,
                :pause    => 1,
                :timeout  => :normal,
            }.merge! opts

            pat = options[:wait_for]
            unless pat.respond_to? :call
              pat = pat.to_s unless pat.is_str? or pat.is_a?(Regexp)
              pat = Regexp.new Regexp::escape(pat) unless pat.is_a? Regexp
            end

            retry_until(options) do

              url = exec
              unless url.is_str?
                url = nil

              else
                Log.Debug "url: |#{url.safe_s}|"

                if pat.respond_to? :call
                  Log.Debug "calling Proc"
                  url = (pat.call url)  ? url : nil

                elsif pat.is_a? Regexp
                  Log.Debug "matching Regexp"
                  url = (url.match pat) ? url : nil

                else
                  raise ArgumentError, "invalid pattern: #{pat.inspect}"
                end
              end

              Log.Debug "after match url: '#{url.safe_s}'"
              url
            end

          end
        }
        Log.Debug "{#{self.class.to_s}.get_url} :=> #{url.safe_s}"
        url
      end
      def _compile_get_url()
        # pass nil into get_url() so it uses the current document
        compile_code( js_set :rc => js_repl(:get_url, nil) )
      end

      ##
      # First, `nav_page` retrieves the browser's current URL.  If the current URL matches
      # the URL provided as a parameter, `nav_page` returns WITHOUT causing Firefox to
      # navigate.  Otherwise, `nav_page` calls MozRepl#goto_url followed by MozRepl#get_url.
      #
      # Returns the current page URL.
      #
      # The default condition is to wait until the browser's URL matches the
      # provided URL.  However, `nav_page` passes all of its parameters to
      # MozRepl#goto_url and MozRepl#get_url.
      #
      # @param url          [String]
      # @param opts         [Hash]
      # @option opts :pause [Integer]
      # (see MozRepl#get_url)
      #
      # @return [String]
      ##
      def nav_page(url, opts = {})
        pageurl = nil
        Log.Debug("[NAV_PAGE '#{url}']") {
          _check_repl_lock

          options = {
              :wait_for => url,
          }.merge! opts

          pageurl = get_url
          if pageurl.respond_to?(:downcase) and pageurl.downcase == url.to_s.downcase
            Log.Debug "ALREADY ON THE CORRECT PAGE; NOT NAVIGATING"
          else
            Log.Debug(:h3, "navigating to '#{url}'") {
              goto_url url, options
              pageurl = get_url options
            }
          end
        }
        Log.Debug "{nav_page} :=> #{pageurl.safe_s}"
        pageurl
      end

      FOUND = 'FOUND'.freeze
      ##
      # Wait for particular elements to appear in the document.
      #
      # @param xpath [Array<(String, ..., Hash)>]
      #
      # @options options
      # @option options :raise [true, String]
      #    (Optional) if the element don't appear within the timeout period,
      #       raise an exception.  When :raise is a String, it specifies the
      #       the text of the exception.  Otherwise, the default exception string
      #       is raised.
      #
      # @return [true, false]
      ##
      def wait_for(*xpath)
        options = {}
        options = xpath.pop if
            xpath.length > 0 and xpath[-1].is_hash?

        raise ArgumentError, "at least 1 xpath must be provided" unless
            xpath.is_array?

        options[:raise] = %Q|Never found '#{xpath[0].to_s}'| if
          options[:raise] == true

        rc = nil
        Log.Debug(:h4, "[WAIT_FOR]") {
          _check_repl_lock

          _compile_wait_for xpath
          rc = exec
          rc = (rc.is_str? and rc.include?(FOUND)) ? true : false

          raise options[:raise] if
              not rc and options[:raise]
        }
        Log.Debug "{wait_for} :=> #{rc.safe_s}"
        rc
      end
      def _compile_wait_for(xpath)
        compile_callback :wait_for_elements,
                         :xpath   => xpath,
                         :on_succ => js_func( js_repl_rc_ok('FOUND') )
      end

      ##
      # Get the referrer.
      #
      # @return [String]
      ##
      def get_referrer()
        rc = nil
        Log.Debug(:h4, "[GET_REFERRER]") {
          _check_repl_lock
          _compile_get_referrer
          rc = exec
          rc.strip! if rc.is_str?
        }
        Log.Debug "{get_referrer} :=> #{rc.safe_s}"
        rc
      end
      def _compile_get_referrer()
        compile_code( js_set :rc => js_repl(:get_referrer, nil) )
      end

      ##
      # Retrieve the HTML of the elements which match the XPath.
      #
      # @param xpath [String]
      # @return [Array<String>]
      ##
      def get_html(xpath)
        rc = nil
        Log.Debug(:h4, "[GET_HTML]") {
          _check_repl_lock
          _compile_get_html xpath
          rc = exec
        }
        Log.Debug "{get_html} :=> ", rc
        rc
      end
      def _compile_get_html(xpath)
        compile_callback :wait_for_elements,
                         :xpath   => xpath,
                         :on_succ => js_on_succ( js_code 'repl.get_html(rc)' )
      end

      ##
      # Retrieve the text of the elements which match the XPath.
      #
      # @param xpath [String]
      # @return [Array<String>]
      ##
      def get_text(xpath)
        rc = nil
        Log.Debug(:h4, "[GET_TEXT]") {
          _check_repl_lock
          _compile_get_text xpath
          rc = exec
        }
        Log.Debug "{get_text} :=> ", rc
        rc
      end
      def _compile_get_text(xpath)
        compile_callback :wait_for_elements,
                         :xpath   => xpath,
                         :on_succ => js_on_succ( js_code 'repl.get_text(rc)' )
      end

      ##
      # Retrieve the HTML attributes of the element which matches the XPath.
      #
      # @param xpath [String]
      # @return [Hash]
      ##
      def get_attrs(xpath)
        rc = nil
        Log.Debug(:h4, "[GET_ATTRS]") {
          _check_repl_lock
          _compile_get_attrs xpath
          rc = exec
        }
        Log.Debug "{get_attrs} :=> ", rc
        rc
      end
      def _compile_get_attrs(xpath)
        compile_callback :wait_for_elements,
                         :xpath   => xpath,
                         :on_succ => js_on_succ( js_code 'repl.get_attrs(rc)' )
      end

      ##
      # Retrieve the cookies of the current document as a Hash.
      #
      # @return [Hash]
      ##
      def get_doc_cookies()
        cookies = nil
        Log.Debug(:h3, "[GET_COOKIES]") {
          _check_repl_lock
          _compile_get_cookies
          cookies = exec
        }
        Log.Debug "{get_cookies} :=> ", cookies
        cookies
      end
      def _compile_get_doc_cookies()
        compile_code( js_set :rc => js_repl(:get_doc_cookies, nil) )
      end

      ##
      # Iterate through EVERY cookie and select those whose :host matches
      # the provided string.
      #
      # Unlike :get_doc_cookies, :get_all_cookies returns an Array of Hash.
      #
      # @param options [Hash]
      # @option options :host [String]
      # @return [Array<Hash>]
      ##
      def get_all_cookies(options = {})
        raise ArgumentError, ":host is a required parameter" unless
            options[:host].is_str?

        cookies = nil
        Log.Debug(:h3, "[GET_ALL_COOKIES: #{options[:host].to_s}]") {
          _check_repl_lock
          compile_code( js_set :rc =>
                                js_repl(:get_all_cookies, js_json_parms({:host => options[:host]})) )
          cookies = exec
        }
        Log.Debug "{get_all_cookies} :=> ", cookies
        cookies
      end

      CLICKED = 'CLICKED'.freeze

      ##
      # Click on the first element which matches the XPath and wait
      # for the document's +readyState+ attribute to be +complete+.
      #
      # Returns +false+ if the click failed.  If the click failed,
      # we don't bother to wait for a page load.
      #
      # Returns +true+ if both the click and the wait for load are
      # successful.
      #
      # Returns :clicked if the click was successful but the load
      # failed.
      #
      # @param xpath [String]     XPath of element to click on
      # @param options [Hash]     See MozRepl#get_url
      #
      # @return [false, :clicked, true]
      ##
      def click(xpath, options = {})
        rc = nil
        Log.Debug(:h4, "[CLICK]") {
          _check_repl_lock
          _compile_click xpath
          rc = exec
          Log.Debug "do_click rc: #{rc.safe_s}"
          unless rc == CLICKED
            # unable to click on element => total failure
            rc = false
          else
            # give the browser some time to get the navigation going
            sleep 0.5

            # we clicked!
            unless wait_page_load
              # page didn't seem to load properly
              rc = :clicked
            else
              # finding the element, clicking on it and waiting for the
              # page to load succeeded.  if caller wants us to wait for
              # particular conditions, we'll do it, but the caller has to
              # figure out if those conditions were ultimately satisfied.
              rc = true
              get_url options if options[:wait_for]
            end
          end
        }
        Log.Debug "{click} :=> #{rc.safe_s}"
        rc
      end
      def _compile_click(xpath)
        compile_callback :wait_for_first_element,
                         :xpath   => xpath,
                         :on_succ => js_on_succ( js_code 'repl.do_click(rc)' )
      end
    end

  end
end

require 'mozrepl/actor/forms'
require 'mozrepl/actor/tabs'
require 'mozrepl/actor/inflating'
require 'mozrepl/actor/frames'
