# encoding: utf-8

# mozrepl/actor/inflating.rb
#
# This file contains source code for the class MozRepl::Actor::Base.
# MozRepl::Actor::Base is split among several files to make the code
# easier to navigate.
#
# The methods here:
# * inflate objects from the content of page elements

module MozRepl
  module Actor
    class Base
      ##
      # Evaluate an XPath to produce a root element.  Then use an Inflater to
      # construct an object from the results of evaluating XPaths on that root.
      #
      # Using the Inflater's fields (which contain the XPath expressions),
      # the REPL constructs and returns a JavaScript object, which Ruby
      # initially receives as a Hash.  The Inflater provided with the Hash,
      # and the Inflater constructs the desired Ruby object.
      #
      # @param root [String]
      #    an XPath expression whose result defines the container for the
      #    XPath expressions in +objdesc+
      #
      # @param inflater [MozRepl::Inflater]
      #    a MozRepl::Inflater object which contains the fields
      #
      # @return the object returned by +inflater+
      ##
      def inflate_obj(xpath, inflater)
        obj = nil
        Log.Debug(:h4, "[INFLATE_OBJ]") {
          _check_repl_lock

          compile_callback :wait_for_elements,
                           :xpath   => xpath,
                           :on_succ => js_code(%Q|
function(rc) {
   repl.rc_ok( repl.inflate_obj(rc, #{js_parms(inflater.fields)}) );
}|)

          obj = exec
          obj = inflater.inflate obj if obj.is_hash?
        }
        Log.Debug "{inflate_obj} :=> ", obj
        obj
      end

      ##
      # Evaluate an XPath which produces a list of objects, all of the same "type",
      # and inflate each of those objects.
      #
      # @param root [String]
      # @param inflater [MozRepl::Inflater]
      # @return Array of object returned by +inflater+
      ##
      def inflate_all(xpath, inflater)
        objs = nil
        Log.Debug(:h4, "[INFLATE_ALL]") {
          _check_repl_lock

          compile_callback :wait_for_elements,
                           :xpath   => xpath,
                           :on_succ => js_code(%Q|
function(rc) {
   repl.rc_ok( repl.inflate_all(rc, #{js_parms([inflater.fields])}) );
}|)

          objs = exec

          objs = objs.map { |o| inflater.inflate o } if objs.is_array?
        }
        Log.Debug "{inflate_all} :=> ", objs
        objs
      end
    end

  end
end
