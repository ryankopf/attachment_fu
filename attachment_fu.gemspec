# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name			  = %q{ryankopf-attachment_fu}
  s.authors			= ["Rick Olson", "Steven Pothoven", "Ryan Kopf"]
  s.summary			= %q{attachment_fu as a gem}
  s.description	= %q{This is a fork of Steven Pothoven's fork of Rick Olson's attachment_fu, adding Rails 5 support.}
  s.email			  = %q{ryan@ryankopf.com}
  s.homepage		= %q{http://github.com/ryankopf/attachment_fu}
  s.version			= "5.2.1.10"
  s.date			  = %q{2020-02-04}

  s.files			  = Dir.glob("{lib}/**/*") + %w( CHANGELOG LICENSE README.rdoc amazon_s3.yml.tpl rackspace_cloudfiles.yml.tpl )
  s.extra_rdoc_files  = ["README.rdoc"]
  s.rdoc_options	  = ["--inline-source", "--charset=UTF-8"]
  s.require_paths	  = ["lib"]
  s.rubygems_version  = %q{1.8.29}

  s.requirements << 'aws-sdk-v1, ~> 1.61.0'

  if s.respond_to? :specification_version then
    s.specification_version = 2
  end
end
