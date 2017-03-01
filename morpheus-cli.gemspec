# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'morpheus/cli/version'

Gem::Specification.new do |spec|
  spec.name          = "morpheus-cli"
  spec.version       = Morpheus::Cli::VERSION
  spec.authors       = ["David Estes", "Bob Whiton", "Jeremy Michael Crosbie", "James Dickson"]
  spec.email         = ["davydotcom@gmail.com"]
  spec.summary       = "Provides CLI Interface to the Morpheus Public/Private Cloud Appliance"
  spec.description   = "Morpheus allows one to manage docker containers and deploy applications on the CLI"
  spec.homepage      = "http://www.morpheusdata.com"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0")
  
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.6"
  spec.add_development_dependency "rake"
  spec.add_dependency 'term-ansicolor', '~> 1.3.0'
  spec.add_dependency "rest-client", "2.0.0"
  spec.add_dependency 'multipart-post'
  spec.add_dependency "filesize"
  spec.add_dependency 'mime-types'
  spec.add_dependency "table_print"
end
