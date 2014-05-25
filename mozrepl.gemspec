# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'mozrepl/version'

Gem::Specification.new do |spec|
  spec.name          = 'mozrepl'
  spec.version       = MozRepl::VERSION
  spec.authors       = ['Jake Coughlin']
  spec.email         = ['coughlin.jake@gmail.com']
  spec.summary       = 'Firefox Automation in Ruby'
  spec.description   = "Query and/or control Firefox from any Ruby script (uses the Firefox MozRepl extension)."
  spec.homepage      = 'https://github.com/coughlinjake/mozrepl'
  spec.license       = 'MIT'

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})

  spec.require_paths = ['lib']

  spec.required_ruby_version     = '>= 2.1.2'
  spec.required_rubygems_version = '>= 2.2.2'

  spec.add_development_dependency "bundler", "~> 1.6"
  spec.add_development_dependency "rake"
  spec.add_development_dependency 'byebug'
  spec.add_development_dependency 'awesome_print'
  spec.add_development_dependency 'psych'
  spec.add_development_dependency 'pry'

  spec.add_dependency 'wad'
  spec.add_dependency 'multi_json'
  spec.add_dependency 'oj'
  spec.add_dependency 'posix-spawn'
  spec.add_dependency 'yard',               '~> 0.8.7.4'
  spec.add_dependency 'yard-template-jake', '~> 0.0.3'

end
