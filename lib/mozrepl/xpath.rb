# encoding: utf-8

module MozRepl
  module XPath

    # Given a String containing an XPath expression, return the String in
    # standard form ready for evaluation.
    #
    # @note Essentially, all this does is strip leading/trailing whitespaces.
    #    Adding leading/trailing whitespace can make an XPath more readable
    #    when that XPath is specified in another language's string syntax.
    #
    # @param str [String]
    # @return [String]
    #
    # @example Evaluation-ready XPath expression
    #    foo = :some_id
    #    XPath(%Q{ /html/head/title/[@id="#{foo}"] })
    #       # => '/html/head/title[@id="some_id"]'
    ##
    def XPath(str)
      # leading/trailing whitespace may have been added for readability
      str.sub(/^\s+/, '').sub(/\s+$/, '')
    end

    ##
    # Construct a predicate expression which tests whether a string occurs
    # as a class name in the current node's HTML class attribute.
    #
    # @param klass [String, Symbol]
    # @return [String]
    #
    # @example Look for the li element with class 'foo'.
    #     XPath %Q| .//li[ #{HasClass(:foo)} ] |
    #       # => ".//li[contains(concat(' ', @class, ' '), ' foo ')"
    ##
    def HasClass(klass)
      "contains(concat(' ', @class, ' '), ' #{klass} ')"
    end

    ##
    # Return an XPath which retrieves the content from the meta element
    # corresponding to the specified attribute.
    #
    # @note Only `meta` attributes in the HTML `head` element are examined.
    #
    # @param attr_name [String, Symbol]
    # @param options [Hash]
    # @option options :nocase [true, false]
    # @return [String]
    #
    # @example Look for a meta element
    #    Given the markup:
    #        <html>
    #           <head><meta content="Foo text describing this document." name="description"></head>
    #        </html>
    #
    #    XPath %Q| #{MetaValue(:description)} |
    ##
    AT_NAME = :'@name'.freeze
    def MetaValue(attr_name, options = {})
      an = options[:nocase] ? DownCase(AT_NAME) : AT_NAME
      XPath %Q| /html/head/meta[#{an}="#{attr_name.to_s.downcase}"]/@content |
    end

    ##
    # Return an XPath which translates a value to lowercase.
    #
    # @param str [String, Symbol]
    # @param [String]
    #
    # @example Look for a meta whose name attribute is 'description' regardless
    #    of the attribute's case.
    #
    #    XPath %Q| /html/head/meta[ #{Downcase('@name')}="description" ]/@content |
    ##
    def DownCase(str)
      "translate(#{str.to_s},'ABCDEFGHIJKLMNOPQRSTUVWXYZ','abcdefghijklmnopqrstuvwxyz')"
    end

  end
end
