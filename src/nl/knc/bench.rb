require 'benchmark'

module NL
  module KNC
    # Used by various parts of KNC to record execution times and identify
    # bottlenecks.  Benchmarking can be toggled by visiting the /bench
    # endpoint.
    module Bench
      extend KNCLog

      @@benchmark = ENV['KNC_BENCH'] == 'true' || ENV['KNC_BENCH'] == '1'
      @@benchmark_start = Time.now if @@benchmark
      @@benchresults = {}
      @@benchlock = Mutex.new

      # Records the execution time of the given block under the given label.  If
      # benchmarking is enabled and block takes more than threshold ms, print a
      # message.
      def self.bench(label='', threshold=200, &block)
        unless @@benchmark
          yield
          return
        end

        result = Benchmark.measure(label, &block)

        overtime = result.real * 1000 > threshold
        @@benchlock.synchronize do
          @@benchresults[label] ||= {:count => 0, :time => 0}
          @@benchresults[label][:count] += 1
          @@benchresults[label][:time] += result.real
        end

        if overtime
          log "!!! Overtime: #{label}: #{result.format('cpu=%t clock=%r')} threshold=#{threshold}"
        end
      end

      def self.toggle_bench
        @@benchmark = !@@benchmark
        if @@benchmark
          @@benchmark_start = Time.now
        else
          @@benchmark_end = Time.now
        end
      end

      def self.enabled?
        @@benchmark
      end

      def self.get_benchresults(clear=true)
        results = nil

        @@benchlock.synchronize do
          results = @@benchresults.clone
          @@benchresults.clear if clear
        end

        return results
      end

      def self.elapsed
        @@benchmark_end - @@benchmark_start
      end
    end
  end
end
