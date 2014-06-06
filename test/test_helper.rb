
ENV['JOBMGR_MODE'] ||= 'development'
ENV['RACK_ENV'] = ENV['JOBMGR_MODE']

require 'psych'
require 'pathname'

TEST_ROOT = (Pathname.new(__FILE__).expand_path.dirname).freeze

[
    "#{ENV['HOME']}/usr/local/lib/Ruby",
    (TEST_ROOT + '../lib').to_s,
    TEST_ROOT.to_s,
].each { |p| $LOAD_PATH.unshift(p) unless $LOAD_PATH.include? p }

gem 'minitest'
require 'minitest/autorun'
require 'minitest/reporters'
MiniTest::Reporters.use!

# the run mode must be set BEFORE we require brewed
require 'brewed'

require 'data-utils'

class TestHelper
  DATA_DIR  = (TEST_ROOT + 'data').freeze
  STATE_DIR = (TEST_ROOT + '__state').freeze

  def data_path(*paths)        self.class.data_path(*paths)          end
  def self.data_path(*paths)  ([DATA_DIR, *paths].reduce :+)        end

  def state_path(*paths)        TestHelper.state_path(*paths)        end
  def self.state_path(*paths)  ([STATE_DIR, *paths].reduce :+)      end

  def dump_file(fname, obj)
    File.open(fname, 'w') { |fh| fh.print( Psych.dump(obj) ) }
  end

  def load_file(fname)
    Psych.load_file fname
  end

  def load_string(yamlstr)
    Psych.load yamlstr
  end

  def self.generator()
    TestHelper._generator.succ!
    TestHelper._generator
  end
  def self._generator() @_next ||= 'AA' end

end

$TH = TestHelper.new
