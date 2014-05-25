# encoding: utf-8

require 'date'

module MozRepl

  ##
  ## Inflate XPath results into Ruby objects.
  ##
  class Inflater
    include MozRepl::XPath

    @all_inflaters = {}
    class << self
      attr_accessor :all_inflaters
    end

    attr_reader :fields, :names, :result_class

    def initialize()
      @names  = {}
      @fields = []
      @result_class = nil
    end

    def result(klass)
      @result_class = klass
    end

    ##
    # Retrieve any options defined for the specified field name.
    ##
    def options(name)
      name = name.to_sym
      (names.key? name) ? names[name] : nil
    end

    def reserve(name, type, opts = {})
      name = _name name
      _options name, opts.dup unless opts.empty?
      self
    end

    ##
    ## @note Verify xpath by calling _xpath first because it has no
    ##    side-effects.  _name() has the side-effect of updating the
    ##    object's name index.
    ##

    ##
    # Store the text content of the result node.
    ##
    def text(name, xpath, opts = {})
      xpath = _xpath xpath
      name  = _name name
      fields.push :id    => name,
                  :type  => :text,
                  :xpath => xpath
      _options name, opts.dup unless opts.empty?
      self
    end

    def attr(name, xpath, attr_name, opts = {})
      xpath = _xpath xpath
      name  = _name name
      fields.push :id    => name,
                  :type  => :attr,
                  :attr  => attr_name.to_sym,
                  :xpath => xpath
      _options name, opts.dup unless opts.empty?
      self
    end

    def href(name, xpath, opts = {})
      attr name, xpath, :href, opts
      self
    end

    ##
    # Retrieve the text content of the result node and convert to
    # to DateTime.
    #
    # The XPath should always result with an element node.  If an
    # attribute is required, specify the attribute's name with the
    # +:attr+ option.
    #
    # @example Datetime in an element
    #     datetime :first_aired, './date'
    # @example Datetime in an attribute
    #     datetime :first_aired, './episode', :attr => :first_aired
    ##
    def datetime(name, xpath, opts = {})
      if opts[:attr].is_str?
        attr name, xpath, opts[:attr], opts
      else
        text name, xpath, opts
      end
      options(name)[:default].unshift( lambda { |val| val.is_str? ? DateTime.parse(val) : val } )
      self
    end

    def date(name, xpath, opts = {})
      if opts[:attr].is_str?
        attr name, xpath, opts[:attr], opts
      else
        text name, xpath, opts
      end
      options(name)[:default].unshift( lambda { |val| val.is_str? ? Date.strptime(val, '%m/%d/%Y') : val } )
      self
    end

    ##
    # Inflate a separate object whose root node is provided by the XPath.
    # Then store that object in this object under the named property.
    #
    # If a block is given, then only name and xpath should be passed in.
    #
    # Otherwise, no block is given and a name, xpath and an Inflate object
    # should be passed in.
    ##
    def obj(name, xpath, *parms, &block)
      xpath  = _xpath xpath
      name   = _name name

      subobj =
        if block_given?
          raise ArgumentError, "providing an Inflater object along with a block is invalid" if
            parms.length > 0
          Inflater.new().instance_eval(&block)
        else
          raise ArgumentError, "expected an Inflater object" unless
              parms.length == 1
          parms.shift
        end

      fields.push :id    => name,
                  :type  => :obj,
                  :xpath => xpath,
                  :obj   => subobj.fields

      _options name, :obj => subobj

      self
    end

    ##
    #
    # @example Inflate a list of episodes which are defined by a block
    #     list(:episodes, xpath) do
    #        text :season,    './td[@class="c0"]'
    #        text :episode,   './td[@class="c1"]/a'
    #     end
    #
    # @example Inflate a list of EpisodeInflater objects
    #     list :episodes, xpath, EpisodeInflater
    ##
    def list(name, xpath, *parms, &block)
      xpath  = _xpath xpath
      name   = _name name

      subobj =
          if block_given?
            raise ArgumentError, "providing an Inflater object along with a block is invalid" if
                parms.length > 0
            Inflater.new().instance_eval(&block)
          else
            raise ArgumentError, "expected an Inflater object" unless parms.length == 1
            parms.shift
          end

      fields.push :id    => name,
                  :type  => :list,
                  :xpath => xpath,
                  :obj   => subobj.fields

      _options name, :obj => subobj

      self
    end

    ##
    # Temporarily focus the evaluations to a particular node, making that node
    # the root node for the duration of the block.
    #
    # @example
    #    with('./meta_data') do
    #        text name, './name'
    #    end
    ##
    def with(xpath, &block)
      xpath  = _xpath xpath

      # :with implements its localization of a new root node
      # by creating a subobj which evaluates the XPath expr
      # in the :with block...
      subobj = Inflater.new().instance_eval(&block)

      # push the fields down into subobj
      fields.push :type  => :obj,
                  :xpath => xpath,
                  :obj   => subobj.fields

      # ...after the subobj is built, however, its  properties are
      # moved from the subobj into this object and the subobj
      # is discarded.  so post-processing belongs here
      subobj.names.each_pair do |nm, opt|
        _name nm
        _options nm, opt
      end

      self
    end

    ##
    # Process the JavaScript object returned by the REPL and represented as a
    # Ruby Hash.
    ##
    def inflate(hashes)
      rc = []

      hashlist = (hashes.is_a? Array) ? hashes : [hashes]
      hashlist.each do |hash|

        obj = result_class.new
        rc << obj

        names.each_pair do |nm, opts|
          if hash.key?(nm)
            val = hash[nm]

            if opts[:obj].nil?
              obj[nm] = val
            else
              if val.is_a? Array
                val = val.map { |v| opts[:obj].inflate v }
              else
                val = opts[:obj].inflate hash[nm]
              end
              obj[nm] = val
            end

            if opts[:default].length > 0
              if val.is_a? Array
                val = val.map do |v|
                  opts[:default].reduce(v) { |acc, defobj| defobj.call acc }
                end
              else
                val = opts[:default].reduce(val) { |acc, defobj| defobj.call acc }
              end
              obj[nm] = val
            end

          end
        end
      end

      (hashes.is_a? Array) ? rc : rc.shift
    end

    ##
    # If an Inflater already exists for this class, return the existing Inflater
    # object.  Otherwise, create a new Inflater by executing the block.
    ##
    def self.define(&block)
      klass = self.to_s.to_sym

      unless MozRepl::Inflater.all_inflaters.key? klass
        MozRepl::Inflater.all_inflaters[klass] =
            self.new().instance_eval(&block)
        MozRepl::Inflater.all_inflaters[klass]._finalize
      end

      MozRepl::Inflater.all_inflaters[klass]
    end

    def _finalize()
      @result_class = Struct.new *names.keys if result_class.nil?
    end

    private

    def _name(name)
      name = name.to_sym
      raise ArgumentError, "property name '#{name}' already defined" if
          names.key? name

      names[name] = {
          :name    => name,
          :default => [],
      }

      name
    end

    def _options(name, opts = {})
      # we want to ADD to :default rather than replace it
      # so remove :default from options
      optdef = opts.delete :default

      names[name].merge! opts

      names[name][:default] += [*optdef].flatten unless
            optdef.nil? or (optdef.respond_to?(:empty?) and optdef.empty?)

      names[name]
    end

    def _xpath(xpath)
      raise ArgumentError, "expected xpath to be a String" unless xpath.is_str?
      xpath
    end

  end
end
