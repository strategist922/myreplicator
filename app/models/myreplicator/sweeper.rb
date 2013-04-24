module Myreplicator
  class Sweeper
   
    @queue = :myreplicator_sweeper # Provided for Resque
    
    ##
    # Main method provided for resque
    # Reconnection provided for resque workers
    ##
    def self.perform
      Myreplicator::Log.clear_deads
      Myreplicator::Log.clear_stucks
      ActiveRecord::Base.configurations.keys.each do |db|
        Myreplicator::VerticaLoader.clean_up_temp_tables(db)
      end
    end
    
  end
end