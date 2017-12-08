#!/usr/bin/env ruby
#
require 'thread'

queue=Queue.new

queue.push Time.now.to_i

puts queue.inspect

def work(queue)
	puts queue.inspect
	loop {
		begin
			sleep 1 if queue.empty?
			next if queue.empty?
			v=queue.pop(false)
			puts "Found on queue: #{v}"
		rescue Interrupt => e
			queue.push Time.now.to_i
		end
	}
end

thread = Thread.new(work(queue))

thread.join

