# encoding: utf-8

# mozrepl/actor/frames.rb
#
# This file contains source code for the class {MozRepl::Actor::Base}.
# {MozRepl::Actor::Base} is split among several files to make the code
# easier to navigate.
#
# This file also provides a new class, {MozRepl::Actor::Frames}.
# MozRepl::Actor::Frames provides the same Actor interface as
# MozRepl::Actor, but each of the methods locates the current
# frame's document object and operates specifically on that document.
#
# To switch to a different frame, use {MozRepl::Actor::Frames#switch_to}
#
# The methods here:
#
# * provide {MozRepl::Actor::Base#get_frames}
#
# * provide frame-aware versions of click, etc.

module MozRepl
  module Actor

    class Base
      ##
      # Retrieve information about the browser's frames.
      ##
      def get_frames()
        rc = nil
        Log.Debug(:h3, "[#{self.class.to_s}.GET_FRAMES]") {
          _check_repl_lock
          code( js_set :rc => js_repl(:get_frames_info) )
          rc = compile_exec
        }
        Log.Debug "{#{self.class.to_s}.get_frames} :=>", rc
        rc
      end
    end

    ##
    ## MozRepl::Actor::Frames
    ##
    class Frames < Base
      attr_accessor :frame_url

      ##
      # Switch to a different frame.
      #
      # @param frame_url [String]
      # @return [void]
      ##
      def switch_to(frame_url)
        self.frame_url = frame_url
      end

      ##
      # Compile version of get_url() which handles frames.
      ##
      def _compile_get_url()
        unless frame_url.is_str?
          super
        else
          _code_frame_doc
          code( js_set :rc => js_repl(:get_url, js_get(:frame_doc)) )
          compile
        end
      end

      ##
      # Click on an element in this frame.
      ##
      def _compile_click(xpath)
        raise NoFrameURL unless frame_url.is_str?
        compile_callback :frame_wait_for_first_element,
                         :frame_url => frame_url,
                         :xpath     => xpath,
                         :on_succ   => js_on_succ( js_code 'repl.do_click(rc)' )
      end

      ##
      # Get the HTML of an element in this frame.
      ##
      def _compile_get_html(xpath)
        raise NoFrameURL unless frame_url.is_str?
        compile_callback :frame_wait_for_elements,
                         :frame_url => frame_url,
                         :xpath     => xpath,
                         :on_succ   => js_on_succ( js_code 'repl.get_html(rc)' )
      end

      ##
      # Get the attributes of an element in this frame.
      ##
      def _compile_get_attrs(xpath)
        raise NoFrameURL unless frame_url.is_str?
        compile_callback :frame_wait_for_elements,
                         :frame_url => frame_url,
                         :xpath     => xpath,
                         :on_succ   => js_on_succ( js_code 'repl.get_attrs(rc)' )
      end

      ##
      # Get the doc cookies from this frame.
      ##
      def _compile_get_doc_cookies()
        raise NoFrameURL unless frame_url.is_str?
        _code_frame_doc
        code( js_set :rc => js_repl(:get_doc_cookies, js_get(:frame_doc)) )
        compile
      end

      ##
      # Get this frame's referrer.
      ##
      def _compile_get_referrer()
        raise NoFrameURL unless frame_url.is_str?
        _code_frame_doc
        code( js_set :rc => js_repl(:get_referrer, js_get(:frame_doc)) )
        compile
      end

      ##
      # Wait until this frame completes loading.
      ##
      def _compile_wait_page_load()
        unless frame_url.is_str?
          super
        else
          _code_frame_doc
          compile_callback :retry_until,
                           :cond => js_code( %Q|function() {
                                                     var rc = frame_doc.readyState;
                                                     return (rc === 'complete') ? rc : null;
                                                   }| )
        end
      end

      ##
      # Locate this frame, evaluate an XPath on its document and return the
      # results immediately.
      ##
      def check_for_html(xpath)
        rc = nil
        Log.Debug(:h4, "[CHECK_FOR_HTML]") {
          _check_repl_lock
          _compile_check_for_html xpath
          rc = exec
        }
        Log.Debug "{check_for_html} :=> ", rc
        rc
      end
      def _compile_check_for_html(xpath)
        compile_code( js_set :rc =>
                            js_repl( :frame_check_for_html,
                                     js_json_parms(:frame_url => frame_url, :xpath => xpath) ) )
      end

      private

      def _code_frame_doc()
        raise NoFrameURL unless frame_url.is_str?
        code( js_set :frame_doc => js_repl(:frame_document, js_json_parms(:frame_url => frame_url)) )
      end

    end

  end
end
