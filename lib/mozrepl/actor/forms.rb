
# encoding: utf-8

# mozrepl/actor/forms.rb
#
# This file contains source code for the class MozRepl::Actor::Base.
# MozRepl::Actor::Base is split among several files to make the code
# easier to navigate.
#
# The methods here:
#   * get the values in form elements
#   * set the values in form elements

module MozRepl
  module Actor

    class Base
      ##
      # Set the current page's form fields to values corresponding to an Array of form field
      # descriptions.
      #
      # The Array of form field descriptions contains one entry for each form field to update.
      # Each entry must specify an XPath which locates the form field and the value to set
      # the field to.  The entry can be either a Hash which contains keys :xpath and :value,
      # or the entry can be a object which provides :xpath and :value methods.
      #
      # @param form_fields [Array<Hash>]
      #    Array of field descriptions, each item must provide an XPath and a value.
      #
      # @return [Array<String,Integer,nil>]
      #    a parallel Array of the values that were actually set or +nil+ if the form
      #    field either wasn't found or couldn't be set to the intended value.
      ##
      def set_form_fields(form_fields)
        rc = nil
        Log.Debug(:h4, "[SET_FORM_FIELDS]") {
          _check_repl_lock

          rc =
              _exec_apply _canonical_fields(:set, form_fields),
                          js_code('function(item) { return repl.set_form_value(item[0], item[1]); }')
        }
        Log.Debug "{set_form_fields} :=> ", rc
        rc
      end

      ##
      # Retrieve the values from a list of form fields in the current page.
      #
      # The list of form fields can be an Array of Strings or an object that
      # provides an :xpath method.
      #
      # Returns a parallel Array containing the values.
      #
      # @param form_fields [Array<String, Object>]
      #    Array of String (the String is assumed to be the XPath) or Object
      #    which provides an :xpath method
      #
      # @return [Array<String, Integer, nil>]
      ##
      def get_form_fields(form_fields)
        rc = nil
        Log.Debug(:h4, "[GET_FORM_FIELDS]") {
          _check_repl_lock

          rc =
              _exec_apply _canonical_fields(:get, form_fields),
                          js_code('function(xpath) { return repl.get_form_value(xpath); }')
        }
        Log.Debug "{get_form_fields} :=> ", rc
        rc
      end

      def _exec_apply(xpaths, func)
        compile_code( js_set :rc => js_repl(:apply, xpaths, func) )
        exec
      end

      def _canonical_fields(action, form_fields)
        raise ArgumentError, "expected :form_fields to be a non-empty Array" unless
            form_fields.is_array?

        form_fields.map.with_index do |field, index|
          xpath, value =
              case field
                when String     then [field, nil]
                when Array      then field
                when Hash       then [ field[:xpath], field[:value] ]
                else
                  raise ArgumentError, "form field index #{index} provides no :xpath method" unless
                      field.respond_to? :xpath
                  field.xpath
              end

          raise ArgumentError, "field at index #{index}: expected :xpath to be a non-empty String" unless
              xpath.is_str?

          raise ArgumentError, "field at index #{index}: expected :value to be a non-empty String" if
              action == :set and not value.is_str?

          (action == :get) ? xpath : [xpath, value]
        end
      end

    end
  end
end
