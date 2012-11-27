require "thread"

module Myreplicator
  class Parallelizer

    attr_accessor :queue

    def initialize *args
      options = args.extract_options!
      @queue = Queue.new
      @threads = []
      @max_threads = options[:max_threads].nil? ? 10 : options[:max_threads]     
    end

    ##
    # Runs while there are jobs in the queue
    # Waits for a second and checks for available threads
    # Exits when all jobs are allocated in threads
    ##
    def run
      @done = false
      @manager_running = false

      while @queue.size > 0
        if @threads.size <= @max_threads
          @threads << Thread.new(@queue.pop) do |proc|
            Thread.current[:status] = 'running' # Manually Set Thread state for Checks
            Transporter.new.instance_exec(proc[:params], &proc[:block])
            Thread.current[:status] = 'done' 
          end
        else
          manage_threads unless @manager_running
          sleep 1
        end
      end   

      # Waits until all threads are completed
      # Before exiting
      while !@done
        sleep 1
      end

    end
    
    ##
    # Clears dead threads, 
    # frees thread pool for more jobs
    # Exits when no more threads are left
    ##
    def manage_threads
      Thread.new do 
        while(@threads.size > 0)
          done = []
          @threads.each do |t|
            done << t if t[:status] == "done"
          end

          done.each{|d| @threads.delete(d)} # Clear dead threads
          
          # If no more jobs are left, mark done

          if @queue.size == 0 && @threads.size == 0
            @done = true
          else
            sleep 2 # Wait for more threads to spawn
          end

        end
      end
    end

  end
end
