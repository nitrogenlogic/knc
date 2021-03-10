module NL
  module KNC
    # A simple ring buffer that stores the last n objects in the order they
    # were added.  Used for the event log.
    class RingBuffer
      # Initializes a new RingBuffer with the given size.  Size may also be a
      # hash returned by RingBuffer#store, in which case the RingBuffer will be
      # initialized to the state of the RingBuffer that produced the hash.
      def initialize(size = 100)
        if size.is_a?(Hash)
          self.load size
          return
        end

        raise "Size must be greater than or equal to 1, not #{size}" if size < 1
        @readptr = 0
        @writeptr = 0
        @size = 0
        @buf = Array.new(size)
      end

      # Reinitializes the ring buffer with the given hash returned by
      # RingBuffer#store.
      def load(hash)
        raise "#{hash.inspect} is not a hash." unless hash.is_a?(Hash)
        raise 'This is not a valid RingBuffer hash.' unless hash[:ringbuf]

        buf = hash[:buf]
        readptr = hash[:readptr]
        writeptr = hash[:writeptr]
        size = hash[:size]

        expected_size = (writeptr - readptr) % buf.length
        while expected_size < 0
          expected_size += buf.length
        end

        if expected_size == 0 && size == buf.length
          expected_size = buf.length
        end

        if expected_size != size
          raise "The given RingBuffer hash contains invalid data.  Expected size: #{expected_size}, got size: #{size}"
        end

        @buf = buf
        @readptr = readptr
        @writeptr = writeptr
        @size = size
      end

      # Returns a hash of the ring buffer, suitable for loading with
      # RingBuffer#load.
      def store
        {
          :ringbuf => true,
          :buf => @buf.clone,
          :readptr => @readptr,
          :writeptr => @writeptr,
          :size => @size
        }
      end

      # Adds a new item to the end of the buffer.  If the buffer is full, the
      # oldest item will be overwritten.
      def push(obj)
        @buf[@writeptr] = obj
        @writeptr += 1
        if @writeptr == @buf.length
          @writeptr = 0
        end
        if @size == @buf.length
          @readptr += 1
          if @readptr == @buf.length
            @readptr = 0
          end
        else
          @size = @size + 1
        end
      end

      # Returns and removes the first item in the buffer.  Returns nil if the
      # buffer is empty.
      def shift
        return nil if @size == 0

        obj = @buf[@readptr]
        @buf[@readptr] = nil
        @readptr += 1
        if @readptr == @buf.length
          @readptr = 0
        end
        @size -= 1

        obj
      end

      # Yields each element of the buffer to the given block, without
      # removing any.
      def each(&block)
        if @readptr + @size > @buf.length
          for i in @readptr..(@buf.length - 1) do
            yield @buf[i]
          end
          for i in 0..(@readptr + @size - @buf.length - 1)
            yield @buf[i]
          end
        else
          for i in @readptr..(@readptr + @size - 1)
            yield @buf[i]
          end
        end
      end

      def to_a
        # FIXME: This is a dumb implementation of to_a
        a = []
        self.each do |v|
          a << v
        end
        a
      end

      # Removes all elements from the buffer.
      def clear
        @writeptr = 0
        @readptr = 0
        @size = 0
        @buf.fill nil
      end

      # Returns the number of elements in the buffer.
      def length
        @size
      end
    end
  end
end
