# -*- encoding: utf-8 -*-
require_relative "lib/attachment_fu/version"

Gem::Specification.new do |spec|
  spec.name			    = %q{attachment_fu}
  spec.authors			= ["Rick Olson", "Steven Pothoven", "Ryan Kopf"]
  spec.summary			= %q{attachment_fu as a gem}
  spec.description	= %q{This is a fork of Steven Pothoven's fork of Rick Olson's attachment_fu, adding Rails 5 support.}
  spec.email			  = %q{ryan@ryankopf.com}
  spec.homepage		  = %q{http://github.com/ryankopf/attachment_fu}
  spec.version		  = AttachmentFu::VERSION
  spec.date			    = %q{2021-01-30}

  spec.files			       = Dir.glob("{lib}/**/*") + %w( CHANGELOG LICENSE README.rdoc amazon_s3.yml.tpl rackspace_cloudfiles.yml.tpl )
  spec.extra_rdoc_files  = ["README.rdoc"]
  spec.rdoc_options	     = ["--inline-source", "--charset=UTF-8"]
  #spec.require_paths	   = ["lib"]
  spec.rubygems_version  = %q{1.8.29}

  spec.requirements << 'aws-sdk-v1, ~> 1.61.0'

  if spec.respond_to? :specification_version then
    spec.specification_version = 2
  end
end
