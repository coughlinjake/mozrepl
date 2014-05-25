# encoding: utf-8

# mozrepl/actor/tabs.rb
#
# This file contains source code for the class MozRepl::Actor::Base.
# MozRepl::Actor::Base is split among several files to make the code
# easier to navigate.
#
# The methods here operate on browser tabs.

module MozRepl
  module Actor

    class Base
      ABOUT_BLANK = 'about:blank'.freeze

      ##
      # Close all of the browser's current tabs, then open a new, fresh tab.
      ##
      def tabs_reset()
        rc = nil
        Log.Debug(:h3, "[TABS_RESET]") {
          _check_repl_lock
          compile_callback :tabs_reset, {}
          rc = exec
          rc = (rc.is_str? and rc == ABOUT_BLANK) ? true : false
          new_client if rc
        }
        Log.Debug "{tabs_reset} :=> #{rc.safe_s}"
        rc
      end

      ##
      # Open a new tab.
      ##
      def add_tab()
        tabs = nil
        Log.Debug(:h3, "[ADD_TAB]") {
          _check_repl_lock
          compile_callback :tab_new
          tabs = exec
          new_client
        }
        Log.Debug "{add_tab} :=> ", tabs
        tabs
      end

      ##
      # Return information about ALL open tabs.
      ##
      def get_all_tabinfo()
        tabs = nil
        Log.Debug(:h3, "[GET_ALL_TABINFO]") {
          _check_repl_lock
          compile_code( js_set :rc => js_repl(:get_all_tabs_info) )
          tabs = exec
        }
        Log.Debug "{get_all_tabinfo} :=> ", tabs
        tabs
      end

      ##
      # Return information about the currently selected tab.
      #
      # @return [Hash]
      ##
      def selected_tab()
        tab = nil
        Log.Debug(:h3, "[SELECTED_TAB]") {
          _check_repl_lock
          code( js_set :rc => js_repl(:selected_tab) )
          code( _js_throw_no_tab [:selected, nil] )

          code( js_set :rc => js_repl(:tab_info, js_get(:rc)) )

          tab = compile_exec
        }
        Log.Debug "{selected_tab} :=> ", tab
        tab
      end

      ##
      # Return info about the first tab which satisfies the provided criteria.
      #
      # @param tab_selector [Integer, String]
      #    if tab_selector is an Integer, it is the tabbrowser_index of the tab
      #    to activate.  otherwise, tab_selector must be a String containing a
      #    a pattern (NOT a Regexp!).  the first tab whose location matches
      #    the pattern is used.
      #
      # @return [Hash]
      ##
      def tab_info(tab_selector)
        rc = nil
        Log.Debug(:h3, "[TAB_INFO]") {
          _check_repl_lock

          findtab_parms = _find_first_tab_parms(tab_selector)

          code( js_set :rc => js_repl(:find_first_tab, *findtab_parms) )
          code( _js_throw_no_tab findtab_parms )

          code( js_set :rc => js_repl(:tab_info, js_get(:rc)) )

          tab = compile_exec
        }
        Log.Debug "{tab_info} :=> ", tab
        rc
      end

      ##
      # Activate the first tab which satisfies the provided criteria.
      #
      # @param see MozRepl::Base#tab_info
      #
      # @return the same information as selected_tab
      ##
      def activate_tab(tab_selector)
        rc = nil
        Log.Debug(:h3, "[ACTIVATE_TAB]") {
          _check_repl_lock

          findtab_parms = _find_first_tab_parms(tab_selector)

          code( js_set :rc => js_repl(:find_first_tab, *findtab_parms) )
          code( _js_throw_no_tab findtab_parms )

          code( js_set :rc => js_repl(:tab_activate, js_get(:rc)) )

          rc = compile_exec
          if rc == true
            Log.Debug "activate_tab successful; restarting client..."
            new_client
          end
        }
        Log.Debug "{activate_tab} :=> #{rc.safe_s}"
        rc
      end

      ##
      # Close the first tab which satisfies the provided criteria.
      #
      # If tab_selector is nil or not provided, the currently selected tab
      # is used.
      #
      # Otherwise, see MozRepl::Base#tab_info
      ##
      def close_tab(tab_selector = nil)
        rc = nil
        Log.Debug(:h3, "[CLOSE_TAB]") {
          _check_repl_lock

          findtab_parms = nil
          if tab_selector.nil?
            code( js_set :rc => js_repl(:selected_tab) )
            findtab_parms = [:selected, nil]
          else
            findtab_parms = _find_first_tab_parms(tab_selector)
            code( js_set :rc => js_repl(:find_first_tab, *findtab_parms) )
          end

          code( _js_throw_no_tab findtab_parms )

          code( js_set :rc => js_repl_funcs(:tab_close, js_get(:rc)) )

          rc = compile_exec
          if rc == true
            Log.Debug "tab_close successful; restarting client..."
            new_client
          end
        }
        Log.Debug "{close_tab} :=> #{rc.safe_s}"
        rc
      end

      private

      ##
      # The Ruby tab methods allow a tab_selector to be a single object which is
      # either an Integer (for a tab index) or a String (for a URL).  The
      # JavaScript REPL functions, however, represent the tab selector with 2
      # values: [Integer, String].
      #
      # Convert the single Ruby tab selector to a JavaScript array selector.
      #
      # @param tab_selector [Integer, String]
      # @return [Array<(Integer, String)>]
      ##
      def _find_first_tab_parms(tab_selector)
        raise ArgumentError, "activate_tab requires a String for the url pattern" unless
            tab_selector.is_a?(Integer) or tab_selector.is_str?
        (tab_selector.is_a? Integer) ? [tab_selector, nil] : [nil, tab_selector]
      end

      ##
      # Return the JS code which verifies the return value of find_first_tab()
      # and throws an exception if no tab was found.
      #
      # Pass the tab selector in so we can provide a useful exception message.
      #
      # @param findtab_parms [Array<(Integer, String)>]
      # @return [JsValue]
      ##
      def _js_throw_no_tab(findtab_parms)
        p = findtab_parms[0].nil? ? "URL '#{findtab_parms[1]}'" : "index '#{findtab_parms[0]}'"
        js_code %Q|if (!rc) { throw new Error("find_first_tab() with #{p} failed"); }|
      end

=begin
      ##
      # Close any tabs which were opened since the provided tab state.
      #
      # @param tabinfo [Hash]   the return value from MozRepl::Base#get_all_tabinfo
      # @return [true, false]   whether all commands succeeded or not
      #
      def restore_tabs(tabsthen)
        tabsthen = (tabsthen || []).dup

        Log.Debug(:h3, "[RESTORE_TABS]") {
          Log.Debug "PREVIOUS TABS", tabsthen

          keeptabs = []
          tabsnow  = []
          done = false
          while not done do

            if tabsnow.empty?
              tabsnow = get_all_tabinfo
              break if not tabsnow.is_array? or tabsnow.length <= keeptabs.length
              (0...keeptabs.length).each { tabsnow.shift }
              Log.Debug "RELOADED CURR TABS", tabsnow
            end

            tabnow  = tabsnow.shift
            tabthen = tabsthen.shift

            if tabthen.is_hash? and tabnow[:location] == tabthen[:location]
              Log.Debug "** CURRENT TAB'S A KEEPER!"
              keeptabs.push tabthen
            else
              Log.Debug "** CLOSING CURRENT TAB"
              # after we close this tab, we need to refresh tabsnow.
              # refreshing tabsnow means that tabsnow will start
              # with the tabs we've already decided are keepers.
              #
              # however, tabsthen does NOT get a refresh.  it remains
              # at whatever tab we just removed.
              #
              # therefore, after refreshing tabsnow, we'll need to
              # skip over the keepers to bring tabsnow and tabsthen in sync.
              close_tab tabnow[:tabbrowser_index].to_i
              tabsnow = []
            end
          end
        }
      end
=end

    end

  end
end
