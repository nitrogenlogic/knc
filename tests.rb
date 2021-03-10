#!/usr/bin/env ruby
# Some very limited tests of the KNC code.
# (C)2014 Mike Bourgeous

# TODO: Use RSpec
require 'bundler/setup'

require_relative 'src/nl/knc'

require 'yaml'
require 'msgpack'


NL::KNC::Bench.toggle_bench unless ENV['KNC_NOBENCH'] # Enable knc.rb benchmarking


def test_bench name, count, &block
	puts "Running #{count} iterations of '#{name}'"
	result = Benchmark.measure do
		count.times &block
	end
	puts result.format("#{count} iterations: cpu=%t clock=%r")
	puts "#{count / result.real} per second"
	puts
end

def assert expression, expected = true, msg=nil
	raise "Assertion failed (expected '#{expected}', got '#{expression}')#{" #{msg}" if msg}" if expression != expected
end


# Test urikvp
test_bench 'String#urikvp', 20000 do
	assert 'a=1&b=2&c=3&d=4&e=5'.urikvp, {'a' => '1', 'b' => '2', 'c' => '3', 'd' => '4', 'e' => '5'}
	assert 'a=1&a=2&a=3&a=4&a=5'.urikvp, {'a' => '5'}
	assert 'a[]=1&a[]=2&a[]=3'.urikvp, {'a[]' => ['1', '2', '3']}
end


# Test Condition
c_conditions = [
	NL::KNC::KncAction::AlwaysCondition.new,
	NL::KNC::KncAction::BooleanCondition.new,
	NL::KNC::KncAction::ComparisonCondition.new,
	NL::KNC::KncAction::PercentComparisonCondition.new,
	NL::KNC::KncAction::ThresholdCondition.new,
	NL::KNC::KncAction::PercentThresholdCondition.new,
	NL::KNC::KncAction::RangeCondition.new,
	NL::KNC::KncAction::PercentRangeCondition.new
]
c_tests = [
	# Test booleans
	[false, nil, [true, false, true, false, false, false, false, false]],
	[true, nil, [true, true, false, true, false, true, false, false]],
	[0, 0..1, [true, false, true, false, false, false, false, false]],
	[1, 0..1, [true, true, false, true, false, true, false, false]],
	[0, 0..100, [true, false, true, false, false, false, false, false]],
	[1, 0..100, [true, true, false, false, false, false, false, false]],
	[0, nil, [true, false, true, false, false, false, false, false]],
	[1, nil, [true, true, false, false, false, false, false, false]],

	# Test large values, percent range
	[5000, nil, [true, true, false, true, true, true, false, false]],
	[-5000, nil, [true, true, false, false, false, false, false, false]],
	[5000, -12000..12000, [true, true, false, true, true, true, false, true]],
	[-5000, -12000..12000, [true, true, false, false, false, false, false, true]],

	# Test percent threshold (default 51/49 rise/fall)
	[150, 100..200, [true, true, false, true, false, false, true, true]],
	[150.9, 100..200, [true, true, false, true, false, false, true, true]],
	[151, 100..200, [true, true, false, true, false, true, true, true]],
	[150.9, 100..200, [true, true, false, true, false, true, true, true]],
	[150, 100..200, [true, true, false, true, false, true, true, true]],
	[149.1, 100..200, [true, true, false, false, false, true, true, true]],
	[149, 100..200, [true, true, false, false, false, false, true, true]],
	[150, 100..200, [true, true, false, true, false, false, true, true]],

	# Test threshold (default 250/150 rise/fall), percent threshold, range
	[149, -2300..2700, [true, true, false, false, false, false, true, true]],
	[150, -2300..2700, [true, true, false, false, false, false, true, true]],
	[249, -2300..2700, [true, true, false, true, false, false, false, true]],
	[249.9, -2300..2700, [true, true, false, true, false, false, false, true]],
	[250, -2300..2700, [true, true, false, true, true, true, false, true]],
	[249.9, -2300..2700, [true, true, false, true, true, true, false, true]],
	[249, -2300..2700, [true, true, false, true, true, true, false, true]],
	[200, -2300..2700, [true, true, false, true, true, true, true, true]],
	[150.1, -2300..2700, [true, true, false, false, true, true, true, true]],
	[150, -2300..2700, [true, true, false, false, false, false, true, true]],
	[149.9, -2300..2700, [true, true, false, false, false, false, true, true]],
	[150.1, -2300..2700, [true, true, false, false, false, false, true, true]],
	[200, -2300..2700, [true, true, false, true, false, false, true, true]],
]
test_bench "Test Condition class", 1000 do
	c_tests.each_with_index do |test, testnum|
		c_conditions.each_with_index do |val, idx|
			assert val.pass(test[0], test[1]),
				test[2][idx],
				"Test #{testnum}: #{val.to_s.split(' ').join}Condition.pass #{test[0]}, #{test[1]}"
		end
	end
end

# Test rules
r1 = NL::KNC::KncAction.add_rule
r2 = NL::KNC::KncAction.add_rule
assert r1.trigger, nil
assert r1.true_action, nil
assert r1.false_action, nil
assert r2.trigger, nil
assert r2.true_action, nil
assert r2.false_action, nil

h1 = r1.to_h
r3 = NL::KNC::KncAction.rule_from_hash h1
h3 = h1.clone
h3[:id] = r3.id
assert r3.to_h, h3

assert r3.trigger, nil
assert r3.true_action, nil
assert r3.false_action, nil

r1.trigger = NL::KNC::KncAction::TimerTrigger.new
r3.trigger = NL::KNC::KncAction::RandomTrigger.new
r1.filter.edge = false
r2.filter.edge = false
r3.filter.edge = true
r1.condition = NL::KNC::KncAction::PercentComparisonCondition.new
r3.condition = NL::KNC::KncAction::ThresholdCondition.new
r1.true_action = NL::KNC::KncAction::LogAddEventAction.new
r3.true_action = NL::KNC::KncAction::LogAddEventAction.new
r1.false_action = NL::KNC::KncAction::LogAddEventAction.new
r3.false_action = NL::KNC::KncAction::LogAddEventAction.new

err = false
begin
	r3.trigger['Minimum'] = -25
	r3.trigger['Minimum'] = -25.3
rescue
	err = true
end
assert err, true

r3.trigger[r3.trigger.find_parameter('Maximum')] = 1730
r1.trigger['Interval (seconds)'] = 2.25
r3.false_action['Message'] = 'This is a message.'
r1.true_action['Event Details'] = false

assert r1.trigger.is_a?(NL::KNC::KncAction::TimerTrigger)
assert r1.filter.edge, false
assert r1.condition.is_a?(NL::KNC::KncAction::PercentComparisonCondition)
assert r1.true_action.is_a?(NL::KNC::KncAction::LogAddEventAction)
assert r1.false_action.is_a?(NL::KNC::KncAction::LogAddEventAction)
assert r1.trigger['Interval (seconds)'], 2.25
assert r2.trigger, nil
assert r2.filter.edge, false
assert r2.condition.is_a?(NL::KNC::KncAction::AlwaysCondition)
assert r2.true_action, nil
assert r2.false_action, nil
assert r3.trigger.is_a?(NL::KNC::KncAction::RandomTrigger)
assert r3.filter.edge, true
assert r3.condition.is_a?(NL::KNC::KncAction::ThresholdCondition)
assert r3.true_action.is_a?(NL::KNC::KncAction::LogAddEventAction)
assert r3.false_action.is_a?(NL::KNC::KncAction::LogAddEventAction)
assert r3.trigger[r3.trigger.find_parameter('Minimum')], -25
assert r3.trigger['Maximum'], 1730
assert r1.false_action['Message'], nil
assert r3.false_action['Message'], 'This is a message.'
assert r1.true_action['Event Details'], false

r4 = NL::KNC::KncAction.rule_from_hash JSON.parse(r1.to_json, :symbolize_names => true)
r5 = NL::KNC::KncAction.rule_from_hash JSON.parse(r2.to_json, :symbolize_names => true)
r6 = NL::KNC::KncAction.rule_from_hash JSON.parse(r3.to_json, :symbolize_names => true)

assert r4.trigger.is_a?(NL::KNC::KncAction::TimerTrigger)
assert r4.filter.edge, false
assert r4.condition.is_a?(NL::KNC::KncAction::PercentComparisonCondition)
assert r4.true_action.is_a?(NL::KNC::KncAction::LogAddEventAction)
assert r4.false_action.is_a?(NL::KNC::KncAction::LogAddEventAction)
assert r5.trigger, nil
assert r5.filter.edge, false
assert r5.condition.is_a?(NL::KNC::KncAction::AlwaysCondition)
assert r5.true_action, nil
assert r5.false_action, nil
assert r6.trigger.is_a?(NL::KNC::KncAction::RandomTrigger)
assert r6.filter.edge, true
assert r6.condition.is_a?(NL::KNC::KncAction::ThresholdCondition)
assert r6.true_action.is_a?(NL::KNC::KncAction::LogAddEventAction)
assert r6.false_action.is_a?(NL::KNC::KncAction::LogAddEventAction)

assert r4.trigger['Interval (seconds)'], 2.25
assert r6.trigger['Maximum'], 1730
assert r6.trigger[r6.trigger.find_parameter('Minimum')], -25
assert r4.false_action['Message'], nil
assert r6.false_action['Message'], 'This is a message.'
assert r4.true_action['Event Details'], false

h6 = r6.to_h(false)
assert h6[:id], 5
h6[:id] = 47
r47 = NL::KNC::KncAction.rule_from_hash h6
assert r47.id, 47
assert r47.to_h(false), h6
r48 = NL::KNC::KncAction.rule_from_hash h6
assert r48.id, 48
h6[:id] = 13
r13 = NL::KNC::KncAction.rule_from_hash h6
assert r13.id, 13
r49 = NL::KNC::KncAction.rule_from_hash h6
assert r49.id, 49
r50 = NL::KNC::KncAction.add_rule
assert r50.id, 50

h6[:id] = 53
r53 = NL::KNC::KncAction.rule_from_hash JSON.parse(h6.to_json, :symbolize_names => true)
assert r53.id, 53
assert r53.to_json(:noinfo => true), h6.to_json



# Test RingBuffer
test_bench "Test RingBuffer class", 10000 do
	rbuf = NL::KNC::RingBuffer.new(5)
	assert rbuf.length, 0
	assert rbuf.shift, nil
	rbuf.push 'foo'
	assert rbuf.length, 1
	assert rbuf.shift, 'foo'
	assert rbuf.length, 0
	assert rbuf.shift, nil
	rbuf.push 'zero'
	rbuf.each do |v|
		assert v, 'zero'
	end
	rbuf.push 'one'
	assert rbuf.length, 2
	rbuf.shift
	assert rbuf.length, 1
	rbuf.push 'two'
	rbuf.push 'three'
	rbuf.push 'four'
	rbuf.push 'five'
	assert rbuf.length, 5
	a = []
	rbuf.each do |v|
		a.push v
	end
	assert a, [ 'one', 'two', 'three', 'four', 'five' ]

	# Test storing/loading ringbuffer contents
	h = rbuf.store
	rbuf2 = NL::KNC::RingBuffer.new(h)
	assert rbuf2.length, rbuf.length
	rbuf2.push 'sixth'
	assert rbuf2.length, 5
	a = []
	rbuf2.each do |v|
		a.push v
	end
	assert a, [ 'two', 'three', 'four', 'five', 'sixth' ]


	rbuf.push :six
	assert rbuf.length, 5
	a = []
	rbuf.each do |v|
		a.push v
	end
	assert a, [ 'two', 'three', 'four', 'five', :six ]
	assert rbuf.shift, 'two'
	assert rbuf.length, 4
	assert rbuf.shift, 'three'
	assert rbuf.length, 3
	assert rbuf.shift, 'four'
	assert rbuf.length, 2
	a = []
	rbuf.each do |v|
		a.push v
	end
	assert a, [ 'five', :six ]
	assert rbuf.shift, 'five'
	assert rbuf.length, 1
	assert rbuf.shift, :six
	assert rbuf.length, 0
	assert rbuf.shift, nil
	assert rbuf.length, 0


	# More store/load testing
	assert rbuf2.length, 5
	h = rbuf2.store
	rbuf.load h
	assert rbuf.length, rbuf2.length
	a = []
	rbuf.each do |v|
		a.push v
	end
	b = []
	rbuf2.each do |v|
		b.push v
	end
	assert a, b

	# Test .to_a
	a = rbuf.to_a
	assert a, b
	rbuf.clear
	8.times do |i|
		rbuf.push((i + 3) * 3)
	end
	a = [ 18, 21, 24, 27, 30 ]
	b = []
	rbuf.each do |v|
		b.push v
	end
	assert b, a
	b = rbuf.to_a
	assert a, b
end

# Test basic key-value pair parsing (TODO: remove in favor of knd_client specs)
test_bench 'Test basic key-value pair parsing', 10000 do
	assert('a=b c=d'.kin_kvp,	{'a' => 'b', 'c' => 'd'})
	assert('a=b c = d e= f g =h i=" j"'.kin_kvp, {'a' => 'b', 'i' => ' j'})
	assert('"a="b "c="="=d" e"=f"'.kin_kvp, {'c=' => '=d', 'e"' => 'f"'})
	assert('a=""'.kin_kvp,		{'a' => ''})
	assert('a="'.kin_kvp,		{'a' => ''})
	assert('a="\\x20"'.kin_kvp,	{'a' => ' '})
	assert('a="\\x20'.kin_kvp,	{'a' => ' '})
	assert('a=\\x20'.kin_kvp,	{'a' => '\\x20'})
	assert('a=b'.kin_kvp,		{'a' => 'b'})
	assert('"a"="b"'.kin_kvp,	{'a' => 'b'})
	assert('"a"=b'.kin_kvp,		{'a' => 'b'})
	assert('"a"="b'.kin_kvp,	{'a' => 'b'})
	assert('a="b"'.kin_kvp,		{'a' => 'b'})
	assert('a=5'.kin_kvp,		{'a' => 5})
	assert('a=0'.kin_kvp,		{'a' => 0})
	assert('a=-5'.kin_kvp,		{'a' => -5})
	assert('a="5"'.kin_kvp,		{'a' => '5'})
	assert('a=-0'.kin_kvp,		{'a' => 0})
	assert('a=1.5'.kin_kvp,		{'a' => 1.5})
	assert('a=-1.5'.kin_kvp,	{'a' => -1.5})
	assert('a=1e5'.kin_kvp,		{'a' => 1e5})
	assert('a=1.1e5'.kin_kvp,	{'a' => 1.1e5})
	assert('a=-3E5'.kin_kvp,	{'a' => -3e5})
	assert('a=-3.0E5'.kin_kvp,	{'a' => -3e5})
	assert('a=-3E5.0'.kin_kvp,	{'a' => '-3E5.0'})
	assert('a=.25'.kin_kvp,		{'a' => 0.25})
	assert('a=+3'.kin_kvp,		{'a' => 3})
	assert('a=+3e+5'.kin_kvp,	{'a' => 3.0E5})
	assert('a=+3e+'.kin_kvp,	{'a' => '+3e+'})
	assert('a=+3e'.kin_kvp,		{'a' => '+3e'})
	assert('a=+e'.kin_kvp,		{'a' => '+e'})
	assert('a=-e3'.kin_kvp,		{'a' => '-e3'})
	assert('a=-3.e1'.kin_kvp,	{'a' => '-3.e1'})
	assert('a=-3.e.1'.kin_kvp,	{'a' => '-3.e.1'})
	assert('a=0.'.kin_kvp,		{'a' => 0.0})
	assert('a=-5.'.kin_kvp,		{'a' => -5.0})
	assert('a=1.e0'.kin_kvp,	{'a' => '1.e0'})
	assert('a=.'.kin_kvp,		{'a' => '.'})
	assert('a=+'.kin_kvp,		{'a' => '+'})
	assert('a=-'.kin_kvp,		{'a' => '-'})
end

# Test basic key-value pair generation
test_bench 'Test basic key-value pair generation', 10000 do
	assert({a: 1, b: 2, 'c' => 3, d: 4.0}.to_kvp, '"a"=1 "b"=2 "c"=3 "d"=4.0')
	assert({a: -1, b: 2, c: '3', d: 'four'}.to_kvp.kin_kvp, {'a' => -1, 'b' => 2, 'c' => '3', 'd' => 'four'})
end

$ten_full = [
	'xmin=-273 ymin=831 zmin=2660 xmax273 ymax=1036 zmax3108 px_xmin=259 px_ymin=6 px_zmin=960 px_xmax=381 px_ymax=80 px_zmax=979 occupied=0 pop=0 maxpop=9028 xc=0 yc=0 zc=0 sa=0 name="Projector"',
	'xmin1625 ymin136 zmin=4662 xmax1868 ymax797 zmax=4970 px_xmin79 px_ymin=138 px_zmin=1017 px_xmax=124 px_ymax=224 px_zmax=1022 occupied=1 pop=668 maxpop=3870 xc=1665 yc439 zc=4915 sa4456 name="Office_Door"',
	'xmin=-1594 ymin285 zmin=840 xmax=1533 ymax335 zmax=4032 px_xmin=0 px_ymin=0 px_zmin=678 px_xmax=639 px_ymax=198 px_zmax=1005 occupied=0 pop=0 maxpop=126522 xc=0 yc=0 zc=0 sa=0 name="Theater"',
	'xmin=-1199 ymin346 zmin=3780 xmax896 ymax=710 zmax=5138 px_xmin=178 px_ymin=127 px_zmin=1000 px_xmax=510 px_ymax=200 px_zmax=1024 occupied=0 pop=0 maxpop=24236 xc=0 yc=0 zc=0 sa=0 name="Theater2"',
	'xmin=-394 ymin=-170 zmin=5124 xmax668 ymax=706 zmax=5936 px_xmin=242 px_ymin=158 px_zmin=1024 px_xmax=366 px_ymax=259 px_zmax=1033 occupied=0 pop=0 maxpop=12524 xc=0 yc=0 zc=0 sa=0 name="Theater3"',
	'xmin364 ymin=-478 zmin=5852 xmax1108 ymax797 zmax=6342 px_xmin207 px_ymin=159 px_zmin=1032 px_xmax=286 px_ymax=289 px_zmax=1037 occupied=0 pop=76 maxpop=10270 xc=833 yc=49 zc=5876 sa7246 name="Stairs"',
	'xmin=-440 ymin=-467 zmin=5824 xmax182 ymax=694 zmax=6832 px_xmin=302 px_ymin=169 px_zmin=1032 px_xmax=365 px_ymax=288 px_zmax=1041 occupied=0 pop=0 maxpop=7497 xc=0 yc=0 zc=0 sa=0 name="Laundry"',
	'xmin=-1807 ymin=-398 zmin=3430 xmax=-1564 ymax=-11 zmax=3710 px_xmin=573 px_ymin=241 px_zmin=990 px_xmax=637 px_ymax=309 px_zmax=998 occupied=0 pop=0 maxpop=4352 xc=0 yc=0 zc=0 sa=0 name="Touchscreen"',
	'xmin1609 ymin273 zmin=3290 xmax1716 ymax649 zmax=3668 px_xmin=7 px_ymin=122 px_zmin=986 px_xmax=57 px_ymax=196 px_zmax=997 occupied=0 pop=0 maxpop=3700 xc=0 yc=0 zc=0 sa=0 name="Theater_Bright"',
	'xmin=-629 ymin=411 zmin=3905 xmax=-447 ymax=519 zmax=4339 px_xmin=381 px_ymin=161 px_zmin=1003 px_xmax=416 px_ymax=183 px_zmax=1012 occupied=0 pop=0 maxpop=770 xc=0 yc=0 zc=0 sa=0 name="Lightbright"'
]

$hundred_partial = [
	'occupied=1 pop=668 maxpop=3870 xc=1666 yc=447 zc=4914 sa=4454 name="Office_Door"',
	'occupied=0 pop=76 maxpop=10270 xc=840 yc=220 zc=5893 sa=7288 name="Stairs"',
	'occupied=1 pop=688 maxpop=3870 xc=1665 yc=440 zc=4911 sa=4582 name="Office_Door"',
	'occupied=0 pop=60 maxpop=10270 xc=835 yc=210 zc=5861 sa=5690 name="Stairs"',
	'occupied=1 pop=608 maxpop=3870 xc=1663 yc=423 zc=4909 sa=4045 name="Office_Door"',
	'occupied=1 pop=552 maxpop=3870 xc=1666 yc=401 zc=4915 sa=3682 name="Office_Door"',
	'occupied=0 pop=32 maxpop=10270 xc=838 yc=243 zc=5861 sa=3034 name="Stairs"',
	'occupied=1 pop=684 maxpop=3870 xc=1662 yc=433 zc=4905 sa=4543 name="Office_Door"',
	'occupied=0 pop=4 maxpop=12524 xc=206 yc=-34 zc=5170 sa=2951 name="Theater3"',
	'occupied=0 pop=60 maxpop=10270 xc=836 yc=261 zc=5861 sa=5690 name="Stairs"',
	'occupied=1 pop=608 maxpop=3870 xc=1667 yc=408 zc=4909 sa=4046 name="Office_Door"',
	'occupied=0 pop=0 maxpop=12524 xc=0 yc=0 zc=0 sa=e+00 name="Theater3"',
	'occupied=0 pop=44 maxpop=10270 xc=838 yc=223 zc=5861 sa=4172 name="Stairs"',
	'occupied=1 pop=596 maxpop=3870 xc=1663 yc=414 zc=4904 sa=3957 name="Office_Door"',
	'occupied=0 pop=80 maxpop=10270 xc=836 yc=155 zc=5861 sa=7587 name="Stairs"',
	'occupied=1 pop=656 maxpop=3870 xc=1667 yc=450 zc=4920 sa=4385 name="Office_Door"',
	'occupied=0 pop=72 maxpop=10270 xc=835 yc=119 zc=5872 sa=6854 name="Stairs"',
	'occupied=1 pop=620 maxpop=3870 xc=1666 yc=411 zc=4914 sa=4134 name="Office_Door"',
	'occupied=0 pop=80 maxpop=10270 xc=838 yc=99 zc=5897 sa=7681 name="Stairs"',
	'occupied=1 pop=600 maxpop=3870 xc=1665 yc=421 zc=4916 sa=4003 name="Office_Door"',
	'occupied=0 pop=68 maxpop=10270 xc=838 yc=115 zc=5903 sa=6543 name="Stairs"',
	'occupied=1 pop=620 maxpop=3870 xc=1665 yc=426 zc=4914 sa=4134 name="Office_Door"',
	'occupied=0 pop=48 maxpop=10270 xc=832 yc=118 zc=5869 sa=4565 name="Stairs"',
	'occupied=1 pop=644 maxpop=3870 xc=1667 yc=440 zc=4918 sa=4302 name="Office_Door"',
	'occupied=1 pop=720 maxpop=3870 xc=1665 yc=444 zc=4921 sa=4815 name="Office_Door"',
	'occupied=0 pop=80 maxpop=10270 xc=813 yc=182 zc=5886 sa=7654 name="Stairs"',
	'occupied=1 pop=608 maxpop=3870 xc=1666 yc=418 zc=4914 sa=4054 name="Office_Door"',
	'occupied=0 pop=76 maxpop=10270 xc=834 yc=95 zc=5904 sa=7314 name="Stairs"',
	'occupied=1 pop=624 maxpop=3870 xc=1665 yc=426 zc=4907 sa=4149 name="Office_Door"',
	'occupied=0 pop=72 maxpop=10270 xc=839 yc=245 zc=5872 sa=6854 name="Stairs"',
	'occupied=1 pop=612 maxpop=3870 xc=1662 yc=427 zc=4910 sa=4074 name="Office_Door"',
	'occupied=0 pop=60 maxpop=10270 xc=836 yc=284 zc=5867 sa=5703 name="Stairs"',
	'occupied=1 pop=628 maxpop=3870 xc=1666 yc=410 zc=4914 sa=4187 name="Office_Door"',
	'occupied=0 pop=80 maxpop=10270 xc=836 yc=210 zc=5870 sa=7612 name="Stairs"',
	'occupied=1 pop=700 maxpop=3870 xc=1663 yc=432 zc=4919 sa=4676 name="Office_Door"',
	'occupied=0 pop=68 maxpop=10270 xc=841 yc=197 zc=5897 sa=6529 name="Stairs"',
	'occupied=1 pop=676 maxpop=3870 xc=1666 yc=438 zc=4912 sa=4503 name="Office_Door"',
	'occupied=0 pop=48 maxpop=10270 xc=835 yc=144 zc=5869 sa=4565 name="Stairs"',
	'occupied=0 pop=4 maxpop=9028 xc=-162 yc=924 zc=3055 sa=1030 name="Projector"',
	'occupied=0 pop=52 maxpop=10270 xc=834 yc=141 zc=5868 sa=4944 name="Stairs"',
	'occupied=0 pop=0 maxpop=9028 xc=0 yc=0 zc=0 sa=e+00 name="Projector"',
	'occupied=1 pop=604 maxpop=3870 xc=1667 yc=440 zc=4919 sa=4035 name="Office_Door"',
	'occupied=0 pop=64 maxpop=10270 xc=832 yc=87 zc=5873 sa=6095 name="Stairs"',
	'occupied=1 pop=700 maxpop=3870 xc=1663 yc=439 zc=4919 sa=4676 name="Office_Door"',
	'occupied=1 pop=688 maxpop=3870 xc=1665 yc=431 zc=4922 sa=4602 name="Office_Door"',
	'occupied=0 pop=72 maxpop=10270 xc=841 yc=188 zc=5889 sa=6894 name="Stairs"',
	'occupied=1 pop=620 maxpop=3870 xc=1663 yc=425 zc=4910 sa=4128 name="Office_Door"',
	'occupied=0 pop=60 maxpop=10270 xc=836 yc=92 zc=5861 sa=5690 name="Stairs"',
	'occupied=1 pop=632 maxpop=3870 xc=1663 yc=431 zc=4908 sa=4203 name="Office_Door"',
	'occupied=1 pop=576 maxpop=3870 xc=1664 yc=426 zc=4907 sa=3829 name="Office_Door"',
	'occupied=0 pop=64 maxpop=10270 xc=832 yc=148 zc=5867 sa=6082 name="Stairs"',
	'occupied=1 pop=732 maxpop=3870 xc=1666 yc=450 zc=4921 sa=4894 name="Office_Door"',
	'occupied=0 pop=56 maxpop=10270 xc=804 yc=117 zc=5898 sa=5378 name="Stairs"',
	'occupied=1 pop=668 maxpop=3870 xc=1661 yc=440 zc=4910 sa=4447 name="Office_Door"',
	'occupied=0 pop=4 maxpop=12524 xc=223 yc=-69 zc=5170 sa=2951 name="Theater3"',
	'occupied=0 pop=72 maxpop=10270 xc=832 yc=143 zc=5866 sa=6841 name="Stairs"',
	'occupied=1 pop=696 maxpop=3870 xc=1664 yc=426 zc=4909 sa=4631 name="Office_Door"',
	'occupied=1 pop=584 maxpop=3870 xc=1665 yc=419 zc=4911 sa=3890 name="Office_Door"',
	'occupied=0 pop=0 maxpop=12524 xc=0 yc=0 zc=0 sa=e+00 name="Theater3"',
	'occupied=0 pop=64 maxpop=10270 xc=836 yc=182 zc=5861 sa=6069 name="Stairs"',
	'occupied=1 pop=732 maxpop=3870 xc=1663 yc=442 zc=4914 sa=4880 name="Office_Door"',
	'occupied=0 pop=4 maxpop=12524 xc=206 yc=-34 zc=5170 sa=2951 name="Theater3"',
	'occupied=0 pop=48 maxpop=10270 xc=838 yc=258 zc=5861 sa=4552 name="Stairs"',
	'occupied=1 pop=640 maxpop=3870 xc=1666 yc=417 zc=4915 sa=4269 name="Office_Door"',
	'occupied=0 pop=0 maxpop=12524 xc=0 yc=0 zc=0 sa=e+00 name="Theater3"',
	'occupied=0 pop=68 maxpop=10270 xc=833 yc=187 zc=5878 sa=6487 name="Stairs"',
	'occupied=1 pop=680 maxpop=3870 xc=1665 yc=434 zc=4917 sa=4539 name="Office_Door"',
	'occupied=0 pop=64 maxpop=10270 xc=836 yc=166 zc=5893 sa=6137 name="Stairs"',
	'occupied=1 pop=668 maxpop=3870 xc=1663 yc=431 zc=4912 sa=4450 name="Office_Door"',
	'occupied=0 pop=84 maxpop=10270 xc=837 yc=115 zc=5900 sa=8073 name="Stairs"',
	'occupied=1 pop=652 maxpop=3870 xc=1664 yc=427 zc=4916 sa=4350 name="Office_Door"',
	'occupied=0 pop=60 maxpop=10270 xc=833 yc=37 zc=5867 sa=5703 name="Stairs"',
	'occupied=1 pop=668 maxpop=3870 xc=1666 yc=439 zc=4913 sa=4451 name="Office_Door"',
	'occupied=0 pop=68 maxpop=10270 xc=838 yc=241 zc=5872 sa=6474 name="Stairs"',
	'occupied=1 pop=656 maxpop=3870 xc=1662 yc=433 zc=4909 sa=4365 name="Office_Door"',
	'occupied=0 pop=64 maxpop=10270 xc=834 yc=98 zc=5861 sa=6069 name="Stairs"',
	'occupied=1 pop=708 maxpop=3870 xc=1665 yc=429 zc=4917 sa=4726 name="Office_Door"',
	'occupied=0 pop=100 maxpop=10270 xc=834 yc=122 zc=5864 sa=9496 name="Stairs"',
	'occupied=1 pop=716 maxpop=3870 xc=1664 yc=450 zc=4913 sa=4771 name="Office_Door"',
	'occupied=0 pop=52 maxpop=10270 xc=834 yc=269 zc=5861 sa=4931 name="Stairs"',
	'occupied=1 pop=648 maxpop=3870 xc=1666 yc=436 zc=4919 sa=4330 name="Office_Door"',
	'occupied=0 pop=4 maxpop=12524 xc=206 yc=-34 zc=5170 sa=2951 name="Theater3"',
	'occupied=0 pop=108 maxpop=10270 xc=833 yc=175 zc=5872 sa=1028 name="Stairs"',
	'occupied=1 pop=664 maxpop=3870 xc=1663 yc=437 zc=4903 sa=4407 name="Office_Door"',
	'occupied=0 pop=0 maxpop=12524 xc=0 yc=0 zc=0 sa=e+00 name="Theater3"',
	'occupied=0 pop=68 maxpop=10270 xc=837 yc=71 zc=5910 sa=6558 name="Stairs"',
	'occupied=0 pop=4 maxpop=3700 xc=1715 yc=341 zc=3660 sa=1479 name="Theater_Bright"',
	'occupied=1 pop=652 maxpop=3870 xc=1666 yc=423 zc=4924 sa=4364 name="Office_Door"',
	'occupied=0 pop=0 maxpop=3700 xc=0 yc=0 zc=0 sa=e+00 name="Theater_Bright"',
	'occupied=1 pop=688 maxpop=3870 xc=1663 yc=432 zc=4913 sa=4585 name="Office_Door"',
	'occupied=0 pop=84 maxpop=10270 xc=836 yc=37 zc=5900 sa=8073 name="Stairs"',
	'occupied=1 pop=648 maxpop=3870 xc=1665 yc=433 zc=4913 sa=4319 name="Office_Door"',
	'occupied=0 pop=4 maxpop=12524 xc=206 yc=-34 zc=5170 sa=2951 name="Theater3"',
	'occupied=0 pop=88 maxpop=10270 xc=833 yc=58 zc=5889 sa=8426 name="Stairs"',
	'occupied=1 pop=664 maxpop=3870 xc=1662 yc=417 zc=4912 sa=4423 name="Office_Door"',
	'occupied=0 pop=0 maxpop=12524 xc=0 yc=0 zc=0 sa=e+00 name="Theater3"',
	'occupied=0 pop=68 maxpop=10270 xc=837 yc=191 zc=5890 sa=6514 name="Stairs"',
	'occupied=1 pop=656 maxpop=3870 xc=1666 yc=441 zc=4922 sa=4388 name="Office_Door"',
	'occupied=0 pop=60 maxpop=10270 xc=836 yc=19 zc=5895 sa=5757 name="Stairs"',
	'occupied=1 pop=736 maxpop=3870 xc=1662 yc=436 zc=4909 sa=4897 name="Office_Door"'
]

test_bench "Parse ten full lines with NL::KndClient::Zone.new", 10000 do
	z = nil
	$ten_full.each do |line|
		z = NL::KndClient::Zone.new line
	end
end

test_bench "Parse ten full lines with kin_kvp", 10000 do
	$ten_full.each do |line|
		s = line.kin_kvp
	end
end

test_bench "Parse one hundred partial lines with NL::KndClient::Zone.new", 1000 do
	z = nil
	$hundred_partial.each do |line|
		z = NL::KndClient::Zone.new line
	end
end

test_bench "Parse one hundred partial lines with kin_kvp", 1000 do
	$hundred_partial.each do |line|
		s = line.kin_kvp
	end
end

pack1 = MessagePack.pack(JSON.parse(NL::KndClient::Zone.new($ten_full[1]).to_json))
test_bench "Parse msgpack-encoded zone to hash", 100000 do
	z = MessagePack.unpack(pack1)
end

z1 = NL::KndClient::Zone.new $ten_full[1]
z2 = NL::KndClient::Zone.new $hundred_partial[0]
test_bench "Merge partial zone with full zone", 100000 do
	z1.merge_zone z2
end

h1 = {"xmin"=>-273, "ymin"=>831, "zmin"=>266, "xmax"=>273, "ymax"=>1036, "zmax"=>3108, "px_xmin"=>259, "px_ymin"=>6, "px_zmin"=>960, "px_xmax"=>381, "px_ymax"=>80, "px_zmax"=>979, "occupied"=>false, "pop"=>0, "maxpop"=>9028, "xc"=>0, "yc"=>0, "zc"=>0, "sa"=>0, "name"=>"Projector"}
h2 = {"xmin"=>-1273, "ymin"=>1831, "zmin"=>266, "xmax"=>273, "ymax"=>1036, "zmax"=>3108, "px_xmin"=>259, "px_ymin"=>6, "px_zmin"=>960, "px_xmax"=>381, "px_ymax"=>80, "px_zmax"=>979, "occupied"=>false, "pop"=>0, "maxpop"=>9028, "xc"=>0, "yc"=>0, "zc"=>0, "sa"=>0, "name"=>"Projector2"}
test_bench "Create a hash", 100000 do
	h3 = {"xmin"=>-273, "ymin"=>831, "zmin"=>266, "xmax"=>273, "ymax"=>1036, "zmax"=>3108, "px_xmin"=>259, "px_ymin"=>6, "px_zmin"=>960, "px_xmax"=>381, "px_ymax"=>80, "px_zmax"=>979, "occupied"=>false, "pop"=>0, "maxpop"=>9028, "xc"=>0, "yc"=>0, "zc"=>0, "sa"=>0, "name"=>"Projector"}
end
test_bench "Merge two hashes", 100000 do
	h3 = h1.merge h2
end
test_bench "Merge! two hashes", 100000 do
	h1.merge! h2
end
test_bench "Create new zone from hash", 100000 do
	z = NL::KndClient::Zone.new h1
end
test_bench "Create a new zone from hash without normalizing", 100000 do
	z = NL::KndClient::Zone.new h1, false
end

z1 = NL::KndClient::Zone.new $ten_full[1]
test_bench "Create a zone from kin_kvp-parsed hash", 100000 do
	z2 = NL::KndClient::Zone.new $ten_full[1].kin_kvp
end
raise "kin_kvp zone does not match original zone\n\tz1=#{z1}\n\tz2=#{z2}" if z1 != z2

test_bench "Create a zone from kin_kvp-parsed hash without normalizing", 100000 do
	z2 = NL::KndClient::Zone.new $ten_full[1].kin_kvp, false
end
raise "kin_kvp non-normalized zone does not match original zone\n\tz1=#{z1}\n\tz2=#{z2}" if z1 != z2

test_bench "Parse a zone hash using eval", 100000 do
	h = eval '{"xmin"=>-1273, "ymin"=>1831, "zmin"=>266, "xmax"=>273, "ymax"=>1036, "zmax"=>3108, "px_xmin"=>259, "px_ymin"=>6, "px_zmin"=>960, "px_xmax"=>381, "px_ymax"=>80, "px_zmax"=>979, "occupied"=>false, "pop"=>0, "maxpop"=>9028, "xc"=>0, "yc"=>0, "zc"=>0, "sa"=>0, "name"=>"Projector2"}'
end

jzone = z1.to_json
hash = nil
test_bench "Parse a zone to hash from json", 100000 do
	hash = JSON.parse jzone
end
puts "hash #{hash}"

z = nil
test_bench "Create new zone from parsed json", 100000 do
	z = NL::KndClient::Zone.new JSON.parse(jzone)
end
puts "zone #{z}"

test_bench "Create new zone from parsed json without normalizing", 100000 do
	z = NL::KndClient::Zone.new JSON.parse(jzone), false
end
puts "zone #{z}"

yzone = JSON.parse(z1.to_json).to_yaml
test_bench "Parse a zone to hash from yaml", 100000 do
	hash = YAML.load yzone
end
puts "hash #{hash}"


NL::KNC::Bench.toggle_bench

puts "===== Internal benchmarking data ====="
NL::KNC::Bench.get_benchresults.sort_by{|label, result| -result[:time]}.each do |k, v|
	puts "#{k}:\t#{v[:count]}\t#{v[:time]}s\t(#{v[:time]/v[:count]*1000}ms ea)"
end
