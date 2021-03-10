#!/usr/bin/env ruby
# Web interface for depth camera server setup
# Connects to knd, serves information via http.
# (C)2015 Mike Bourgeous
#
# Benchmarking:
# ruby1.9.1 `which ruby-prof` --replace-progname -p call_tree -f prof.out ./knc.rb

require 'bundler/setup'

require_relative 'src/nl/knc'

EM.threadpool_size = 1
NL::KNC.start_knc ARGV[0]
